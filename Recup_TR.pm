# --- fichier Recup_TR.pm ---
package Recup_TR;

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
	my $imap = Net::IMAP::Simple::SSL->new($liste_param->{'serveur_imap'}) or die Envoi_Mail::mail_simple('Erreur Transf_quality','Impossible de se connecter au serveur : $!', @{$liste_param->{'mail_admin'}});
	$imap->login($liste_param->{'login_mail'} => $liste_param->{'pw_mail'}) or die Envoi_Mail::mail_simple('Erreur Transf_quality','Erreur d\'identification ! : $!', @{$liste_param->{'mail_admin'}});

	#Étape 2 : Parcourt du répertoire de stockage des mails de l'ABES et récupère le nombre de message
	my $nbmsg = $imap->select($liste_param->{'Mail_Rep'}) or die Envoi_Mail::mail_simple('Erreur Transf_quality',"Impossible d\'accéder au dossier $liste_param->{'Mail_Rep'} !", @{$liste_param->{'mail_admin'}});
	print 'Il y a '.$nbmsg." messages dans ce dossier !\n\n";
	#Sortie si 0 message
	if ($nbmsg == 0){
		die Envoi_Mail::mail_simple('Transf_quality : Aucun message à traiter',"L'ABES n'a pas transmis de nouveau fichier", @{$liste_param->{'mail_admin'}});
	}	

 	for(my $i = 1; $i <= $nbmsg; $i++){
       	my $es = Email::Simple->new(join '', @{ $imap->get($i) } );
#       	print "-",$es->header('Subject'),"\n";
		$liste_fichier_dispo{$i}{'Nom_fichier'} = Analyse_sujet_mail($es->header('Subject'));
		$liste_fichier_dispo{$i}{'Date_Modif'} = Analyse_date_envoi_modif($es->body);
		$liste_fichier_dispo{$i}{'Date_Chargement'} = Analyse_date_envoi_chargt($es->header('Date'));		

    }



#Étape 4 : fermeture de la connexion à la boite mail
$imap->quit() or die 'Un problème est survenu avec la méthode quit() !';
return \%liste_fichier_dispo;	
}

#Récupère le fichier de transfert sur le FTP de la DSI
sub Recup_TR{
	my ($liste_param,$nom_fichier) = @_;
	my $f = Net::FTP->new($liste_param->{'ftp_serveur'}) or die Envoi_Mail::mail_simple('Erreur Transf_quality',"Impossible d\'accèder au serveur ftp $liste_param->{'ftp_serveur'}", @{$liste_param->{'mail_admin'}});
	$f->login($liste_param->{'ftp_login'}, $liste_param->{'ftp_pw'}) or die Envoi_Mail::mail_simple('Erreur Transf_quality',"Impossible de se connecter au serveur ftp avec le user $liste_param->{'ftp_login'} !", @{$liste_param->{'mail_admin'}}); 
#	my $dir = ".";
#
#$f->cwd($dir) or die "Can't cwd to $dir\n";
	$f->get($nom_fichier,$liste_param->{'Rep_notices'}.$nom_fichier) or die Envoi_Mail::mail_simple('Erreur Transf_quality',"Le fichier $nom_fichier n'est pas présent sur le ftp", @{$liste_param->{'mail_admin'}});;
	$f->quit;
	return $liste_param->{'Rep_notices'}.$nom_fichier;
}

#Archive le message de l'abes une fois celui-ci traité
sub Archive_message{
	my ($liste_param,$num_message) = @_;
	my $imap = Net::IMAP::Simple::SSL->new($liste_param->{'serveur_imap'}) or die Envoi_Mail::mail_simple('Erreur Transf_quality','Impossible de se connecter au serveur : $!', @{$liste_param->{'mail_admin'}});
	$imap->login($liste_param->{'login_mail'} => $liste_param->{'pw_mail'}) or die Envoi_Mail::mail_simple('Erreur Transf_quality','Erreur d\'identification ! : $!', @{$liste_param->{'mail_admin'}});
	$imap->select($liste_param->{'Mail_Rep'}); 
	$imap->copy( $num_message,$liste_param->{'Mail_rep_Archives'});
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

#A partir de la date de fin de sélection des notices modifiées Ligne NOT du message fourni par l'ABES renvoi la date de modification des notices 
sub Analyse_date_envoi_modif {
	my $message = shift;
	$message =~  m/NOT  Selection end ([0-9]{4})-([0-9]{2})-([0-9]{2}) ([0-9]{2}):([0-9]{2}):([0-9]{2}).*/;
	#Conversion de la date du mail en datetime pour manipulation
	  my $dt = DateTime->new(
      year       => $1,
      month      => $2,
      day        => $3,
      hour       => $4,
      minute     => $5,
      second     => $6,
      time_zone  => 'Europe/Paris',
  );
	return $dt->ymd('').$dt->hms('');
}

#A partir de la date d'envoi du mail de l'abes détermine la date de chargement des TR dans Horizon
sub Analyse_date_envoi_chargt {
	my $mail_date = shift;
	#Conversion de la date du mail en datetime pour manipulation
	$mail_date =~ s/ \(CET\)//g;
	$mail_date =~ s/ \(CEST\)//g;
	print $mail_date,"\n";
	my $dmn = DateTime::Format::Mail->parse_datetime($mail_date);
	
	#Si le mail est envoyé entre 19 h et minuit alors la date de modification des notices est la date du jour sinon c'est la date de la veille
	if ($dmn->hour()>= 19 && $dmn->hour()<= 23){
		#Si le mail est reçu un lundi alors la date de modification est celle du vendredi qui prècède
		return $dmn->add( days => 1 )->mdy('/');
	} 
	else {
		return $dmn->mdy('/');
	}
}

1;