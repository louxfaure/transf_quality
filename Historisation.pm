# --- fichier Historisation.pm ---
package Historisation;
use strict;
use warnings;
use DBI;

sub insert_donnees {
	my ( $liste_variable, $liste_donnees, $date_modif,$date_hist,$type_maj_notice,$etab ) = @_;
	print "date fin -->$date_modif\n";
	my $dbmysql = DBI->connect(
		"DBI:mysql:database=$liste_variable->{'DB_Hist'};host=localhost",
		"$liste_variable->{'DB_Hist_User'}",
		"$liste_variable->{'DB_Hist_Pw'}",
		{ 'RaiseError' => 1 }
	);
	my $requete = "select count(*) from `chargements` where `Date` = '$date_hist' and `Type_action` = '$type_maj_notice' and RCR = '$etab'";
	my $nb_result = $dbmysql->selectrow_array($requete);
	if ($nb_result != 0){
		 $dbmysql->do("delete from `chargements` where `Date` = '$date_hist' and `Type_action` = '$type_maj_notice' and RCR = '$etab'")
	} 
	my $result = $dbmysql->do(
"INSERT INTO `chargements`(`Date`, `Type_Action`, `RCR`, `Nb_notices_abes`, `a_statut_chargement`, `b_doublon`, `c_pb_transl`,`d_200_b`,`e_181_182`,
 `f_date_pub`, `g_collection`, `h_autorites`, `i_auteurs`, `j_resp`, `k_453`,`l_488`,`n_ex_abst`) VALUES ($liste_donnees)"
	);
	$dbmysql->disconnect();
	return $result;
}

sub recup_date_modif {
	my ($liste_variable) = @_;
	my $dbmysql = DBI->connect(
		"DBI:mysql:database=$liste_variable->{'DB_Hist'};host=localhost",
		"$liste_variable->{'DB_Hist_User'}",
		"$liste_variable->{'DB_Hist_Pw'}",
		{ 'RaiseError' => 1 }
	);
	my $requete =
"SELECT DATE_FORMAT( Date, '%Y%m%d%H%i%S' ) FROM chargements ORDER BY Date DESC LIMIT 0 , 1";
	my $result = $dbmysql->selectrow_array($requete);
	$dbmysql->disconnect();
	return $result;
}

1;
