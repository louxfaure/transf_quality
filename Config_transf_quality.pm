# --- fichier Config_transf_quality.pm ---
package Config_transf_quality;

sub Config {
	my %Config = (
		"Mail_Rep"   => 'Horizon/Traitements/Pica_import_SUDOC',
		"Mail_rep_Archives"      => 'Horizon/Traitements/Pica_import_SUDOC/Archives',
		"Mail_DSI_Rep"   => 'Horizon/Traitements/Imports_SUDOC',
		"Mail_DSI_rep_Archives"      => 'Horizon/Traitements/Imports_SUDOC/Archives',
#		"Destinataires"  => ['rebub-catalog@diff.u-bordeaux.fr'],
		"Destinataires"  => [],
		"ftp_serveur"    => '',
		"ftp_login"    => '',
		"ftp_pw"  => '',
		"Rep_notices" => '/home/scoopadmin/IN_PERL/Chargements_SUDOC/Notices/',
		"Rep_logs" => '/home/scoopadmin/OUT_PERL/Chargements_SUDOC/Logs/',
		"Rep_rapports" => '/home/scoopadmin/OUT_PERL/Chargements_SUDOC/Rapports/',
		"Rep_temp" => '/home/scoopadmin/OUT_PERL/Chargements_SUDOC/Temp/',
		"DB_Hist" => 'transf_quality',
		"DB_Hist_User" => 'transf_quality',
		"DB_Hist_Pw" => 'pYqbqpHB6f6htPts',		
	);
	return %Config;
}

1;
