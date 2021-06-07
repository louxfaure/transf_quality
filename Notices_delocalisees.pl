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
use File::Copy "cp";

use Envoi_Mail;
use Requetes_Hz;
use WSAbes;
use Encodage;
use Fichier_Excel;

use Horizon_Info_Bib;
use Recup_TR;
use Config_notices_delocalisees;

use Email::Sender::Simple qw(sendmail);
use Email::Simple;
use Email::Simple::Creator;
use Email::Sender::Transport::SMTPS;
use MIME::Lite;
use Email::MIME::RFC2047::Encoder;



#Gestion de l'encodage
my $encodage = ActiverAccents();

###Paramètres du programme###
print "--> Initialisation dftes paramètres du programme\n";
my %variable = Param::Param();
my %config = Config_notices_delocalisees::Config();
my %liste_param =  (%variable,%config); 
(%variable,%config) = ();

##Initialisation de la liste des rcr Bordelais
my %listercr = MapEtab::listrcr();
$listercr{SANS_EX}{'nom_bib'} = "Notices n'ayant pas pu être rattachées à une bibliothèque";


	
#Récupération de la liste des fichiers à traiter
my $liste_fichier_dispo = Recup_TR::Nom_TR(\%liste_param);
foreach my $key ( keys %{$liste_fichier_dispo} ){
	$liste_fichier_dispo->{$key}{'Nom_fichier'} =~ s/TR/LP/;
	print "--> Début du traitement pour le fichier : $liste_fichier_dispo->{$key}{'Nom_fichier'}\n";
	#Récupération du fichier sur le ftp de la DSI
	my $file_tr = Recup_TR::Recup_TR(\%liste_param,$liste_fichier_dispo->{$key}{'Nom_fichier'});
#	my $file_tr = "/home/scoopadmin/IN_PERL/Chargements_SUDOC//test.mrc";
	my $date_modif_end = $liste_fichier_dispo->{$key}{'Date_Modif'};
#	my $date_chargement = '03/14/2016';
#	my $date_modif = 20160219;
	print "\t$date_modif_end\n";

	#Initialisation de la connexion à la base de données Horizon
	print "--> Connexion à Horizon\n";
	my $dbh = Requetes_Hz::connect_to_horizon($liste_param{'server_hz'},$liste_param{'login_hz'},$liste_param{'pw_hz'}, $liste_param{'bd_prod'});
	
	#Boucle de traitement des fichiers
	print "--> Boucle de traitement des notices délocalisées\n"; 
	my $nb_notices_traitees= Analyse_fichier_TR($dbh,$file_tr,$date_modif_end);
	print "--> Fin de l'analyse des notices\n";
	print Dumper{%listercr};


	#Boucle de rédaction des rapports
	print "--> Début de l'écriture des fichiers\n";
	my ($file_maj_bib)= Redige_Rapport($date_modif_end,$nb_notices_traitees);
	print "--> Fin de l'écriture des rapports\n";
	
	#Deconnexion de la base Horizon
	print "--> Déconnexion de Horizon\n";
	$dbh->disconnect();
	#Envoi du mail
	print "--> Envoi du rapport de traitement\n"; 
	Mail_Rapport($nb_notices_traitees,$file_maj_bib,$date_modif_end);
	#Arcivage du mail de l'ABES
	print "--> Archivage du Mail de l'ABEs\n"; 
	Recup_TR::Archive_message(\%liste_param,$key);

#	
#	#Signalement des anomalies à l'administrateur
#	#Anomalies du WS abes 
#	my $nombre_erreur_ws_abes = @{$liste_erreurs_ws};
#	if ($nombre_erreur_ws_abes > 0){
#		my $message = "Bonjour\n,Le web service de l'Abes renvoyé des erreurs pour les PPN suivants" . join(", ",@{$liste_erreurs_ws})."\n Voir les logs pour plus détails";
#		Envoi_Mail::mail_simple("Transf_quality_erreur",$message,$liste_param{mail_admin});
#	}
	
}
exit 0;		
	

sub Analyse_fichier_TR{
	my ($dbh,$file_tr,$date_modif_end) = @_;
	my $nb_notices_traites = 0;
	
	##Ouverture du fichier
	open(my $fh, '<:encoding(UTF-8)', $file_tr)
		or die "Impossible d'ouvrir '$file_tr' $!";
 
	while (my $ppn = <$fh>) {
		chomp $ppn;
		print "$ppn\n";
		my $Objt_bib = Horizon_Info_Bib->new(
					{
						ENTREE      => $ppn,
						TYPE_ENTREE => "ppn",
						DATABASE    => $dbh,
						ENCODAGE    => $encodage
					}
				);
		#Si il y a une notice dans Horizon je vais voir si j'ai une localisation dans le réseau 
		if ($Objt_bib->{ERROR} eq "false"){
			#On regarde si la notice a été fusionnée
			$Objt_bib->{FUSION} = WSAbes::merged($ppn);
			
			#Maintenant on regarde les localisations
			#On récupère la localisation à partir des exemplaires
			my $requete = "select distinct RBCCN from location where location in (select location from item where bib# = $Objt_bib->{ID_BIB})";
			my $locs = $dbh->selectall_arrayref($requete, { Slice => {} });
			if (! @$locs){
				#Pas d'exemplaire on récupère la localisation à partir de la zone 930 ou 955
				my $requete = "select distinct RBCCN from location where RBCCN in (select substring(text,3,9) from bib where tag in ('930','955') and bib# = $Objt_bib->{ID_BIB})";
				$locs = $dbh->selectall_arrayref($requete, { Slice => {} });
			}
			#On a pas réussi à rattaché la notice à une bibliothèque
			if (! @$locs){
				$listercr{SANS_EX}{Notices}{$Objt_bib->{ID_BIB}} = $Objt_bib;
				next ;
			}
			foreach my $loc (@$locs){
					print "\t$loc->{RBCCN}\n";
					my ($loc_sudoc,$message) = WSAbes::controle_loc_sudoc($ppn,$loc->{RBCCN});
					if ($loc_sudoc ne "True"){
						$listercr{$loc->{RBCCN}}{Notices}{$Objt_bib->{ID_BIB}} = $Objt_bib;
						$nb_notices_traites ++;
					}
					}
				}
			
	}
	return $nb_notices_traites;	
}

##########################
###REDACTION DES RAPPORTS#
##########################
#
##Boucle d'éditition des listes d'anomalies :
##-------------------------------------------
sub Redige_Rapport {
	my ($date_modif,$nb_notices_traitees) = @_;
		#Création du classeur
		my $nom_fichier = $liste_param{'Rep_rapports'}."rapport_notices_supprimees_".$date_modif.".html";
		print $nom_fichier;
		#Ouverture du fichier en écriture
		open my $fho, ">", $nom_fichier or die "$nom_fichier: $!";
		my $html_content = "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional //EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\"\n";
		$html_content = $html_content. "<html xmlns=\"http://www.w3.org/1999/xhtml\">\n";
		$html_content = $html_content. "<body>\n";
		$html_content = $html_content. "<p>Bonjour, Voici la liste des PPN délocalisées la semaine passée. $nb_notices_traitees anomalies ont été identifiées</p>\n";
		$html_content = $html_content. "<p>Bonne semaine,</p>\n";
		$html_content = $html_content. "<p>L'équipe du SCOOP</p>\n";
		$html_content = $html_content. "<p>SCOOP toujours prêt !</p>\n";
		$html_content = $html_content. "<h2>Bibliothèques concernées</h2>\n";
		$html_content = $html_content. '<table style="border-collapse:collapse;border-spacing:0;border-color:#ccc;border-width:1px;border-style:solid">'."\n";
		$html_content = $html_content. "\t<tr>\n";
		$html_content = $html_content. "\t\t".'<th style="font-family:Arial, sans-serif;font-size:14px;font-weight:normal;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#ccc;color:#333;background-color:#f0f0f0;text-align:center;vertical-align:top">Bibliothèque</th>'."\n";
		$html_content = $html_content. "\t\t".'<th style="font-family:Arial, sans-serif;font-size:14px;font-weight:normal;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#ccc;color:#333;background-color:#f0f0f0;text-align:center;vertical-align:top">Nombre d\'anomalies</th>'."\n";
		$html_content = $html_content. "\t</tr>\n";
	 	my @Liste_colonnes = ('PPN', 'Id_Hz','Titre', 'ISBN','ISSN', 'Type de notice', 'Notice fusionnée (PPN de la notice active)');
	 	my @Liste_clefs = ('PPN','ID_BIB','TITRE','ISBN','ISSN','TYPE_DOC','FUSIONS');
	 	#Pour chaque RCR ayant des notices chargées
	 	foreach my $etab( sort keys %listercr ) {
	 		next if (! $listercr{$etab}{Notices});
	 		my $nbr = keys (%{$listercr{$etab}{'Notices'}});
	 		$html_content = $html_content. "\t<tr>\n";
	 		$html_content = $html_content. "\t\t".'<td style="font-family:Arial, sans-serif;font-size:14px;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#ccc;color:#333;background-color:#fff;vertical-align:top"><a href="#'.$etab.'" title="Si ce lien ne fonctionne pas dans votre boîte de messagerie, la liste des notices se trouve sous ce tableau.">'.$listercr{$etab}{'nom_bib'}."</a></td>\n";
	 		$html_content = $html_content. "\t\t".'<td style="font-family:Arial, sans-serif;font-size:14px;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#ccc;color:#333;background-color:#fff;vertical-align:top">'.$nbr."</td>\n";
	 		$html_content = $html_content. "\t</tr>\n";
	 	}
		$html_content = $html_content. "</table>\n";
		$html_content = $html_content. "<h2>Listes des notices en anomalies par bibliothèque</h2>\n";
		foreach my $etab( sort keys %listercr ) {
		 	next if (! $listercr{$etab}{Notices});
		 	$html_content = $html_content. '<table style="border-collapse:collapse;border-spacing:0;border-color:#ccc;border-width:1px;border-style:solid;margin:15px 5px;">'."\n";
		 	$html_content = $html_content. "\t<tr>\n";
		 	$html_content = $html_content. "\t\t".'<th style="font-family:Arial, sans-serif;font-size:14px;font-weight:bold;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#ccc;color:#333;background-color:#f0f0f0;text-align:center;vertical-align:top" colspan="9"><a name="'.$etab.'">'.$listercr{$etab}{'nom_bib'}."</a></th>\n";
		 	$html_content = $html_content. "\t</tr>\n";
		 	$html_content = $html_content. "\t<tr>\n";
		 	foreach my $v (@Liste_colonnes){
		 		$html_content = $html_content. "\t\t".'<th style="font-family:Arial, sans-serif;font-size:14px;font-weight:normal;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#ccc;color:#333;background-color:#f0f0f0;text-align:center;vertical-align:top">'.$v."</th>\n";
		 	}
		 	$html_content = $html_content. "\t</tr>\n";
		 	foreach my $ppn( sort keys %{$listercr{$etab}{'Notices'}} ) {
		 		print Dumper(%{$listercr{$etab}{'Notices'}{$ppn}});
		 		print $listercr{$etab}{'Notices'}{$ppn}{'TITRE'},"\n";
#		 		$html_content = $html_content. "\t\t".'<td style="font-family:Arial, sans-serif;font-size:14px;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#ccc;color:#333;background-color:#fff;vertical-align:top">'.$ppn."</td>\n";
				foreach my $k (@Liste_clefs){
					my $value = $listercr{$etab}{'Notices'}{$ppn}{$k} ? $listercr{$etab}{'Notices'}{$ppn}{$k} : 'null';
		 			$html_content = $html_content. "\t\t".'<td style="font-family:Arial, sans-serif;font-size:14px;padding:10px 5px;border-style:solid;border-width:1px;overflow:hidden;word-break:normal;border-color:#ccc;color:#333;background-color:#fff;vertical-align:top">'.$value."</td>\n";
		 		}
		 	$html_content = $html_content. "\t</tr>\n";

			}
		 	$html_content = $html_content. "</table>\n";	
		}
		$html_content = $html_content. "</body>\n";
		$html_content = $html_content. "</html>\n";
		print $fho $html_content;		
	return ($html_content);
}


sub Mail_Rapport{
	my ($nb_notices_traitees,$file_path,$date_modif_end) = @_;

	my $transport = Email::Sender::Transport::SMTPS->new(
	            host => 'smtpauth.u-bordeaux.fr',
	            ssl  => 'SSL',
	        	debug => 1, # or 1
	);
	my $encoder = Email::MIME::RFC2047::Encoder->new;
	my $sujet_encoded = $encoder->encode_text("délocalisés");
	my $sujet = "[SCOOP] Liste des PPN  ".$sujet_encoded."  du ".substr($date_modif_end,6,2)."/".substr($date_modif_end,4,2)."/". substr($date_modif_end,0,4);
	my $mime = MIME::Lite->new(
			    From		=> 'alexandre.faure@u-bordeaux.fr',
			    "Reply-To"	=> 'alexandre.faure@u-bordeaux.fr',
#			    To			=> 'alexandre.faure@u-bordeaux.fr',
			    To			=> 'rebub-catalog@diff.u-bordeaux.fr',
			    Subject		=> $sujet,
			    Type		=> 'multipart/mixed',
		    );
		    
	
	# Le corps du message
	$mime->attach(
			    Type       => 'text/html',
			    Encoding   => 'quoted-printable',
			    Data       => $file_path
			);
	
	#La PJ
#	(my $filename = $filepath) =~s/.*\///s;
#				print "$filename\n";
#				print "$filepath\n";
#				# Fichiers joints
#				$mime->attach(
#				    Type       => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
#	#				Type 	   => 'application/x-zip-compressed',
#				    Encoding   => 'base64',
#				    Path       => $filepath,
#				    Filename   => $filename,
#				   Disposition => 'attachment'
#				);
	
	sendmail($mime->as_string(), { transport => $transport });
	 
}


