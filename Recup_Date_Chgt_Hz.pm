# --- fichier Recup_Date_Chgt_Hz.pm ---
package Recup_Date_Chgt_Hz;

#Parcourt les mails de transferts SUDOC pour récupérer le nom du dernier fichier envoyé par l'ABES
#Récupère les fichiers sur le FTP de la DSI
#Transfert les nom des fichiers fichiers sous la forme d'une liste

use strict;
use Net::IMAP::Simple::SSL;
use Email::Simple;
use MIME::Parser;
use Envoi_Mail;
use Data::Dumper;
use File::Copy;
use DateTime;
use DateTime::Format::Mail;
use Net::FTP;


sub Nom_TR{
	print "-->Début de la récupération des fichiers de transfert\n";
	print "\t-->Lecture des messages\n";
	my $liste_param = shift;
	my %liste_fichier_dispo = ();
	#Étape 1 : Connexion au serveur mail
	my $imap = Net::IMAP::Simple::SSL->new($liste_param->{'serveur_imap'}) or die Envoi_Mail::mail_simple('Erreur Transf_quality','Impossible de se connecter au serveur : $!', $liste_param->{'mail_admin'});
	$imap->login($liste_param->{'login_mail'} => $liste_param->{'pw_mail'}) or die Envoi_Mail::mail_simple('Erreur Transf_quality','Erreur d\'identification sur le serveur de messagerie ! : $!', $liste_param->{'mail_admin'});

	#Étape 2 : Parcourt du répertoire de stockage des mails de l'ABES et récupère le nombre de message
	my $nbmsg = $imap->select($liste_param->{'Mail_DSI_Rep'}) or die Envoi_Mail::mail_simple('Erreur Transf_quality',"Impossible d\'accéder au dossier $liste_param->{'Mail_DSI_Rep'} !", $liste_param->{'mail_admin'});
	print 'Vous avez '.$nbmsg." messages dans ce dossier !\n\n";
	#Sortie si 0 message
	if ($nbmsg == 0){
		die Envoi_Mail::mail_simple('Transf_quality : Pas de chargement des notices dans Horizon',"Les fichiers n'ont pas été transmis à Horizon" , $liste_param->{'mail_admin'});
	}	

 	for(my $i = 1; $i <= $nbmsg; $i++){
       	my $es = Email::Simple->new(join '', @{ $imap->get($i) } );
		$liste_fichier_dispo{$i} = Analyse_date_envoi_chargt($es->header('Date'));		

    }



#Étape 4 : fermeture de la connexion à la boite mail
$imap->quit() or die 'Un problème est survenu avec la méthode quit() !';
return \%liste_fichier_dispo;	
}


#Archive le message de la DSI une fois celui-ci traité
sub Archive_message{
	my ($liste_param,$num_message) = @_;
	print "$num_message\n";
	print "$liste_param->{'Mail_DSI_rep_Archives'}";
	my $imap = Net::IMAP::Simple::SSL->new($liste_param->{'serveur_imap'}) or die Envoi_Mail::mail_simple('Erreur Transf_quality','Impossible de se connecter au serveur : $!', $liste_param->{'mail_admin'});
	$imap->login($liste_param->{'login_mail'} => $liste_param->{'pw_mail'}) or die Envoi_Mail::mail_simple('Erreur Transf_quality','Erreur d\'identification ! : $!', $liste_param->{'mail_admin'});
	$imap->select($liste_param->{'Mail_DSI_Rep'}); 
	$imap->copy( $num_message,$liste_param->{'Mail_DSI_rep_Archives'});
	$imap->delete($num_message);
	$imap->quit() or die 'Un problème est survenu avec la méthode quit() !';
}


#A partir de l'analyse du sujet du  mail de l'Abes retourne le nom du fichier à télécharger
#Prend en paramètree le sujet du message 
sub Analyse_sujet_mail{
	my $mail_objet = shift;
	my ($JobId,$RunId,$Status) = ($mail_objet =~ m/^For JobId = (.*) and .* = (.*),.* status is (.*)$/);
	my $nom_fichier = "TR".$JobId."R".$RunId."A001.RAW";
	return ($Status,$nom_fichier);
}



#A partir de la date d'envoi du mail de la DSI détermine la date de chargement des TR dans Horizon
sub Analyse_date_envoi_chargt {
	my $mail_date = shift;
	#Conversion de la date du mail en datetime pour manipulation
	$mail_date =~ s/ \(CET\)//g;
	my $dmn = DateTime::Format::Mail->parse_datetime($mail_date);
	return $dmn->mdy('/');
}

1;