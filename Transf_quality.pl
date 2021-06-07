#!/usr/bin/perl -w
use strict;
use warnings;
use XML::LibXML;
use DateTime;
use DBI;
use MARC::Batch;
use MapEtab; 
use Param;
use Encode qw(decode encode);
use utf8;
use Benchmark;
use Data::Dumper;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use File::Basename;
use File::Copy "cp";

use Envoi_Mail;
use Requetes_Hz;
use WSAbes;
use Encodage;
use Fichier_Excel;

use Recup_TR;
use Recup_Date_Chgt_Hz;
use Notice;
use Config_transf_quality;
use Historisation;



#Gestion de l'encodage
my $encodage = ActiverAccents();

###Paramètres du programme###
print "--> Initialisation des paramètres du programme\n";
my %variable = Param::Param();
my %config = Config_transf_quality::Config();
my %liste_param =  (%variable,%config); 
(%variable,%config) = ();

##Initialisation de la liste des rcr Bordelais
my %listercr = MapEtab::listrcr();

#Récupération de la dernière date de modification dans la table des historisation
my $date_modif_start = Historisation::recup_date_modif(\%liste_param);
print "$date_modif_start\n";

#On s'assure que le chargement ait bien eu lieu, présence du mail de la DSI et on récupère la liste des dates de chargements (en fonction de la du message)
##Récupération de la date de chargement dans Horizon
print "--> Récupération de la date de chargement dans Horizon\n";
my $liste_date_chargement = Recup_Date_Chgt_Hz::Nom_TR(\%liste_param);
	
#Récupération de la liste des fichiers à traiter
my $liste_fichier_dispo = Recup_TR::Nom_TR(\%liste_param);
foreach my $key ( keys %{$liste_fichier_dispo} ){
	print "--> Début du traitement pour le fichier : $liste_fichier_dispo->{$key}{'Nom_fichier'}\n";
	#Récupération du fichier sur le ftp de la DSI
	my $file_tr = Recup_TR::Recup_TR(\%liste_param,$liste_fichier_dispo->{$key}{'Nom_fichier'});
#	my $file_tr = "/home/scoopadmin/IN_PERL/Chargements_SUDOC//test.mrc";
	my $date_chargement = $liste_date_chargement->{$key};
	my $date_modif_end = $liste_fichier_dispo->{$key}{'Date_Modif'};
	print "date fin -->$date_modif_end";
#	my $date_chargement = '03/14/2016';
#	my $date_modif = 20160219;

	#Initialisation de la connexion à la base de données Horizon
	print "--> Connexion à Horizon\n";
	my $dbh = Requetes_Hz::connect_to_horizon($liste_param{'server_hz'},$liste_param{'login_hz'},$liste_param{'pw_hz'}, $liste_param{'bd_prod'});
	

	
	#Récupération de la liste des anomalies de chargements
	print "--> Récupération de la liste des anomalies de chargements\n";
	my $liste_erreur_chgt = Controle_erreur_chgt($dbh,$date_chargement);
	print $date_chargement,"\n";
	print Dumper(%{$liste_erreur_chgt});
	
	#Boucle de traitement des fichiers
	print "--> Boucle de traitement des notices du transférées par l'ABES\n"; 
	my ($info_bib, $rcr_liste_bib,$liste_erreurs_ws,$nb_notices_traites,$nb_notices_nonchargees)= Analyse_fichier_TR($dbh,$liste_erreur_chgt,$file_tr,$date_modif_start,$date_modif_end);
	print "--> Fin de l'analyse des notices\n";
	
	#Boucle de rédaction des rapports
	print "--> Début de l'écriture des fichiers\n";
	my ($file_maj_bib,$filetoute_maj)= Redige_Rapport($dbh,$info_bib,$rcr_liste_bib,$date_modif_start,$date_modif_end);
	print "--> Fin de l'écriture des rapports\n";
	
	#Deconnexion de la base Horizon
	print "--> Déconnexion de Horizon\n";
	$dbh->disconnect();
	#Envoi du mail
	print "--> Envoi du rapport de traitement\n";
	Mail_Rapport($nb_notices_traites,$nb_notices_nonchargees,$date_modif_end,$info_bib,$file_maj_bib,$filetoute_maj);
	#Arcivage du mail de l'ABES
	print "--> Archivage du Mail de l'ABEs\n"; 
	Recup_TR::Archive_message(\%liste_param,$key);
	#Archivage du mail de la DSI
	print "--> Archivage du Mail de la DSI\n"; 
	Recup_Date_Chgt_Hz::Archive_message(\%liste_param,$key);
	$date_modif_start = $date_modif_end;
	
	#Signalement des anomalies à l'administrateur
	#Anomalies du WS abes 
	my $nombre_erreur_ws_abes = @{$liste_erreurs_ws};
	if ($nombre_erreur_ws_abes > 0){
		my $message = "Bonjour\n,Le web service de l'Abes renvoyé des erreurs pour les PPN suivants" . join(", ",@{$liste_erreurs_ws})."\n Voir les logs pour plus détails";
		Envoi_Mail::mail_simple("Transf_quality_erreur",$message,$liste_param{mail_admin});
	}
	
}
exit 0;		
	

sub Analyse_fichier_TR{
	my ($dbh,$liste_erreur_chgt,$file_tr,$date_modif_start,$date_modif_end) = @_;
	my %info_bib = ();
	my %rcr_liste_bib = ();
	my @liste_erreurs_ws = ();
	
	##Initialisation d'un objet Marc à partir du fichier des transferts réguliers
	my $batch_tr = MARC::Batch->new('USMARC',$file_tr);
	$batch_tr->strict_off();
	$batch_tr->warnings_off();
	#
	##Initialisation cdes compteurs
	my $num_notice_hz = 0;
	my $nb_notices_sudoc = 0;
	my $nb_notices_non_chargees = 0;
	
	################################################
	#####Boucle de traitement des notices du TR#####
	################################################
	## On parcourt les notices
	while (my $notice = $batch_tr->next()) {
	#Récupération des informations bibliographiques et analyse des anomalies
	########################################################################
	my $Objt_bib = Notice->new($notice);
		my $ppn = $Objt_bib->{PPN};
		#On stocke le résultat dans un Hash
		foreach my $clef ( keys %{$Objt_bib} ){
			$info_bib{$ppn}{$clef}=$Objt_bib->{$clef};
		};
	#Numéro de la notice dans le fichier de chargement Horizon nécessaire pour s'assurer qu'il n'y pas eu de problème de chargement
	if ($Objt_bib->{a_statut_chargement}[0] eq " "){$num_notice_hz ++}
	print "\t$num_notice_hz : $ppn --> $Objt_bib->{a_statut_chargement}[0]\n";
	#On regarde si la notice n'est pas remontée en erreur lors du chargement dans Horizon
	if (exists $liste_erreur_chgt->{$num_notice_hz}){ 
		$info_bib{$ppn}{'a_statut_chargement'} = [$liste_erreur_chgt->{$num_notice_hz}{error_message},1];
		$info_bib{'Erreurs_Horizon'}{$ppn} = $liste_erreur_chgt->{$num_notice_hz}{error_message};
		$nb_notices_non_chargees ++;
		#TODO Récupérer la notice marc pour l'enregistrement
#		open(OUTPUT, '> $liste_param{Rep_rapports}.$ppn.dat') or die $!;
#		print OUTPUT $notice->as_usmarc();
#		close(OUTPUT)
	}
	#On regarde le nombre de notices ayant le même PPN
	my $nb_notices_ss_ppn = Requetes_Hz::requete_nb_notice_ppn($dbh,$ppn);
	$info_bib{$ppn}{'b_doublon'} = ($nb_notices_ss_ppn != 1)? ["$nb_notices_ss_ppn notice(s) liées à la notice $ppn", 1]:["$nb_notices_ss_ppn", 0];
	print "$ppn : $Objt_bib->{TITRE} -- $Objt_bib->{TYPE_NOTICE}\n";
	
	#Liste des localisations
	########################
	#On regarde quel est le dernier établissement à avoir modifié la notice et on récupère la liste des RCR 
	#localisés sous la notice avec, pour chacun d'entre eux la dernière date de modification de l'exemplaire
	my $resp = WSAbes::Qui_et_quand($ppn,15);
	
	#Récupération du RCR responsable de la modification de la notice 
	$info_bib{$ppn}{Resp_modif} =  $resp->{Rcr_modif};
	$info_bib{$ppn}{Date_modif} = $resp->{Date_modif};

	#Si le web service a renvoyé une erreur on passe à la notice suivante
	if ($resp->{Statut} eq 'Echec'){
		push @liste_erreurs_ws,$ppn;
		foreach my $loc ( keys %{$Objt_bib->{LOCALISATION}} ){
				$rcr_liste_bib{'Maj_etab'}{$loc}{'Notices'}{$ppn}{'date_modif'} = $date_modif_start;
			}
	}
	else{
		#Ventilation sur fichier en fonction de la date de modification de la notice
		if ($resp->{Date_modif} >= $date_modif_start and $resp->{Date_modif} <= $date_modif_end and exists $listercr{$resp->{Rcr_modif}}){
			$rcr_liste_bib{'Maj_etab'}{$resp->{Rcr_modif}}{'Notices'}{$ppn}{'date_modif'} = $resp->{Date_modif};
		}  
		my $liste_loc = $resp->{Liste_loc};			
		foreach my $rcr ( keys %{$liste_loc} ){
			next if exists $rcr_liste_bib{$rcr}{'Notices'};
			if ($liste_loc->{$rcr} >= $date_modif_start && $resp->{Date_modif} <= $date_modif_end){
				$rcr_liste_bib{'Maj_etab'}{$rcr}{'Notices'}{$ppn}{'date_modif'} = $liste_loc->{$rcr} 
			}
			else {
				$rcr_liste_bib{'Toute_Maj'}{$rcr}{'Notices'}{$ppn}{'date_modif'} = $liste_loc->{$rcr}
			}
			print "\t-$rcr : $liste_loc->{$rcr}\n";
		}
	}
#	print Dumper ($info_bib{$ppn});
	$nb_notices_sudoc ++;
}

print $nb_notices_sudoc,"\n";
return(\%info_bib,\%rcr_liste_bib,\@liste_erreurs_ws,$nb_notices_sudoc,$nb_notices_non_chargees);
	
}

##########################
###REDACTION DES RAPPORTS#
##########################
#
##Boucle d'éditition des listes d'anomalies :
##-------------------------------------------
sub Redige_Rapport {
	my ($dbh,$info_bib,$rcr_liste_bib,$date_modif,$date_modif_end) = @_;
	my ($file_maj_bib,$filetoute_maj);
	my %liste_erreurs = (
					'a_statut_chargement'=> 'Notice filtrée ou non chargée dans Horizon',
					'b_doublon' => 'Plusieurs ou aucune notices avec le même PPN dans Horizon',
					'c_pb_transl' => 'Absence de champ 200 problème de translittération (200$7 mal renseigné) supposé.',
					'd_200_b' => 'Type de support non renseigné (pas de 200$b ou pas de 181/182)',
					'e_181_182' => 'Notices avec une 181/182 mais sans 183',
					'f_date_pub'=> 'Notices pour lesquelles la date renseignée dans le champ 100 ne correspond pas à celle déclarée en 210$d',
					'g_collection'=>'Notices avec un 225 et sans 410 ou 461',
					'h_autorites'=>'Notices avec une ou plusieurs autorités matières qui n\'ont pas de lien au référentiel IdRef',
					'i_auteurs'=>'Notices avec une ou plusieurs autorités auteur qui n\'ont pas de lien au référentiel IdRef',
					'j_resp'=>'Notices avec une ou plusieurs autorités auteur qui n\'ont pas de mention de responsabilité',
					'k_453' => 'Notices de monographie avec un $0 en 453',
					'l_488' => 'Notices avec un champ 488 sans 311',
					'n_ex_abst' => 'Notice sans exemplaire lié dans Horizon'
	);
	my %type_action = (
		'Maj_etab' => \$file_maj_bib,
		'Toute_Maj' => \$filetoute_maj,
	) ;
		##Pour chaqur type de rapport
	foreach my $type_maj_notice (sort keys %type_action){
		#Création du classeur
#		my $type_maj_notice = ($v == 0) ? 'Maj_etab' : 'Toute_Maj';
		my $nom_fichier = $liste_param{'Rep_rapports'}."rapport_chgt_".$date_modif."_".$type_maj_notice.".xlsx";
		my $titre_classeur = "Rapport de chargement SUDOC : $type_maj_notice";
		my ($workbook,$header,$normal,$error,$fsommaire,$link,$pourcentage,$header2,$normal2) = Fichier_Excel::ouvre_classeur($nom_fichier,$titre_classeur);
		$header->set_text_wrap();
		$normal->set_text_wrap();
		$header2->set_text_wrap();
		$normal2->set_text_wrap();
		$error->set_text_wrap();
		my $alerte = $workbook->add_format(
			bold => 1,
			size => 11,
			border => 2,
			color => 'black',
			bg_color => 'orange',
			border_color => 'black',
			align => 'left',
	);
		$alerte->set_text_wrap();
		#Creation de la feuille sommaire
		my @Liste_colonnes_som = ('Bibliothèque', 'RCR','Lien feuille', 'Nombre de notices fournies par l\'ABES');
		foreach my $erreur (sort keys %liste_erreurs){
				push @Liste_colonnes_som, $liste_erreurs{$erreur};
			}
		my $sommaire = Fichier_Excel::cree_feuille($workbook,$header,'Sommaire',@Liste_colonnes_som);
#		$sommaire->set_column( 0, 0, 40 );
		$sommaire->set_column('A:A',50);
		$sommaire->set_column('B:C',20);
	 	my $som = 1;
	 	my @Liste_colonnes1 = ('PPN', 'Titre', 'ISBN','ISSN', 'Type de notice');
	 	my @Liste_colonnes2 =  ('Statut_chargement','Nombre de notices avec ce même PPN',
	 	 'Pas de titre','Type de support 200$b ou 181/182','183','100/210', '225/410', '6##$3', '7##$0', '7##$4','453$0','488 sans 311',
	 	  'Nombre d\'exemplaires de la division rattachés à la notice','Etablissement responsable de la dernière modification');
	 	#Pour chaque RCR ayant des notices chargées
	 	foreach my $etab( sort keys %{$rcr_liste_bib->{$type_maj_notice}} ) {
			#Alimentation de la feuille de sommaire
			$sommaire->write( $som,0, $listercr{$etab}{'nom_bib'}, $fsommaire );
			$sommaire->write( $som,1, $etab, $fsommaire );
			$sommaire->write( $som,2, 'internal:'.$etab.'!A1',$link );
			#Nombre de notices à charger
			my $nb_notices_a_charger = 0;
			#Création d'une feuille avec en paramètre le titre des colonnes
			my $worksheet = Fichier_Excel::cree_feuille($workbook,$header,$etab,@Liste_colonnes1);
			Fichier_Excel::cree_ligne($worksheet,$header2,0,5,@Liste_colonnes2);
			$worksheet->set_column('A:A',20);
			$worksheet->set_column('B:B',50);
			$worksheet->set_column('C:C',20);
			$worksheet->set_column('E:S',20);
			my $y = 1;
			#Initialisation des compteurs d'erreurs
			foreach my $erreur (sort keys %liste_erreurs){
				$rcr_liste_bib->{$type_maj_notice}{$etab}{'Compteurs'}{$erreur} = 0;
			}
			#Pour chaque notice
			foreach my $ppn( sort keys %{$rcr_liste_bib->{$type_maj_notice}{$etab}{'Notices'}} ) {
				$worksheet->write_string( $y, 0, $ppn,$normal);
				$worksheet->write( $y, 1, decode($encodage,$info_bib->{$ppn}->{TITRE}),$normal);
				$worksheet->write( $y, 2, $info_bib->{$ppn}->{ISBN},$normal);
				$worksheet->write( $y, 3, $info_bib->{$ppn}->{ISSN},$normal);
				$worksheet->write( $y, 4, $info_bib->{$ppn}->{TYPE_NOTICE},$normal);
				my %format = (
					0  => \$normal2,
					1  => \$error,
					2 => \$alerte,
				);
				my $x = 5;
				foreach my $erreur (sort keys %liste_erreurs){
					next if $erreur eq 'n_ex_abst';
					my $code_format = $info_bib->{$ppn}->{$erreur}[1];
					$worksheet->write( $y, $x, $info_bib->{$ppn}->{$erreur}[0],${$format{$code_format}});
					$rcr_liste_bib->{$type_maj_notice}{$etab}{'Compteurs'}{$erreur} += 1 if $code_format != 0;
					$x ++ ;
				}
				#On regarde le nombre d'exemplaires liés à la notice
				my $nb_ex = Requetes_Hz::requete_nb_ex_div_ppn($dbh,$ppn,$listercr{$etab}{'div'});
				my $code_format = ($nb_ex == 0 and $info_bib->{$ppn}->{TYPE_NOTICE} ne "Document électronique ou partie de document électronique (Oa ou Os)")?1:0;
				$worksheet->write( $y, $x, $nb_ex,${$format{$code_format}});
				$rcr_liste_bib->{$type_maj_notice}{$etab}{'Compteurs'}{'n_ex_abst'} += 1 if $code_format != 0;
				$nb_notices_a_charger ++;
				$x++;
				#Ajout de l'établissement responsable de la dernière modification
				print "Rcr modif :",$info_bib->{$ppn}->{Resp_modif},"\n";
				$worksheet->write( $y, $x, $info_bib->{$ppn}->{Resp_modif},$normal2);
				$y ++;
			}
#			print Dumper(%{$rcr_liste_bib->{$type_maj_notice}{$etab}{'Compteurs'}});
			#On prépare les données pour les intégrer dans la base d'historisation
			$date_modif_end =~ m/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})/;
			my $date_hist = $1."-".$2."-".$3." ".$4.":".$5.":".$6;
			my @donnees_hist = ($date_hist,$type_maj_notice,$etab,$nb_notices_a_charger);
			#On ajoute le décompte des erreurs à la page des sommaires
			my $x = 3;
			#Nombre de notices fournies par l'ABES
			$sommaire->write( $som,$x, $nb_notices_a_charger, $fsommaire );
			$x ++;
			#On traite les autres types d'erreurs	
			foreach my $erreur (sort keys %liste_erreurs){
				$sommaire->write( $som,$x, $rcr_liste_bib->{$type_maj_notice}{$etab}{'Compteurs'}{$erreur}, $fsommaire );
				push @donnees_hist, $rcr_liste_bib->{$type_maj_notice}{$etab}{'Compteurs'}{$erreur};
				$x ++;
			}
			$som ++;
			#Historisation des données
			my $liste_donnees = "'".join ("','",@donnees_hist) ."'";
			print "--> Sauvegarde des données d'historisation ok \n"if  Historisation::insert_donnees(\%liste_param,$liste_donnees,$date_modif_end,$date_hist,$type_maj_notice,$etab) == 1;
	 	}
	 	${$type_action{$type_maj_notice}} = $nom_fichier;
	}
	return ($file_maj_bib,$filetoute_maj);
}

#Parcourt la table mistrake d'horizon pour récupérer les erreurs de chargement
sub Controle_erreur_chgt{
	my ($dbh,$date_chargement) = @_;
	my $requete = "select ltrim(substring(error_message,CHARINDEX(':',error_message) + 1,CHARINDEX(',',error_message)-CHARINDEX(':',error_message)-1)) as Num_notice, error_message
from mistrake where appname = 'MARCIN' 
and  date = datediff(dd,'Jan 1 1970', convert(datetime,'$date_chargement'))";
	return $dbh->selectall_hashref($requete, 'Num_notice');
}

sub Mail_Rapport{
	my ($nb_notices_traites,$nb_notices_nonchargees,$date_modif,$info_bib,$file_maj_bib,$filetoute_maj) = @_;
	my $temp_dir_name = $liste_param{'Rep_temp'}."Rapports_chgt_".$date_modif;
	my $file_message = $temp_dir_name."/message.txt";
	mkdir $temp_dir_name if (! -e $temp_dir_name);
	#Ouverture du fichier en écriture
	open my $fho, ">:encoding(utf8)", $file_message or die "$file_message: $!";
	
	
	$date_modif =~ m/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})/;
	my $date_message = $3 ."/". $2 . "/" .$1;
	my $heure_message = $4 ."h".$5;
	#Préparation du mail d'envoi des rapports
	print $fho "Bonjour, Voici les rapports du chargement des $nb_notices_traites notices SUDOC fournies par l'ABES le $date_message à $heure_message.\n
	\tLe fichier rapport_chgt_".$date_modif."_Maj_etab.xlsx correspond aux notices mises à jour par votre bibliothèque ou sous lesquelles vous avez créé ou modifié une localisation.\n
	\tLe fichier rapport_chgt_".$date_modif."_Toute_Maj.xlsx correspond aux notices modifiées par d'autres établissements du réseau SUDOC.\n";
	if ($nb_notices_nonchargees != 0){
		 print $fho "Attention ! $nb_notices_nonchargees notices ont généré des erreurs lors du chargement dans Horizon.\n";
		 foreach my $ppn (sort keys %{$info_bib->{Erreurs_Horizon}}){
		 	print $fho "\t - PPN ".$ppn." : ".$info_bib->{$ppn}{'a_statut_chargement'}[0]."\n";
		 }
	}
	print $fho "Bonne journée,
	Le SCOOP
	SCOOP toujours prêt !";
	#Rédaction des rapports 
#	print "$message\n"; 
	close $fho;
	my $Sujet = "[SCOOP] Rapport de chargement SUDOC des notices modifiées le $date_message";
	(my $filename_maj_bib = $file_maj_bib) =~s/.*\///s;
	(my $filename_toute_maj = $filetoute_maj) =~s/.*\///s;
	cp ($file_maj_bib,$temp_dir_name."/".$filename_maj_bib);
	cp ($filetoute_maj,$temp_dir_name."/".$filename_toute_maj);
#	my @Pj = ($temp_dir_name."machin.zip");
#	Envoi_Mail::mail_simple($Sujet,$message,$liste_param{Destinataires},\@Pj);
	 
}




