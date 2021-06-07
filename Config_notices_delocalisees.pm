# --- fichier Config_notices_delocalisees.pm ---
package Config_notices_delocalisees;

sub Config {
	my %Config = (
		"Mail_Rep"   => 'Horizon/Traitements/Pica_delocalisation_SUDOC',
		"Mail_rep_Archives"      => 'Horizon/Traitements/Pica_delocalisation_SUDOC/Archives',
		"Destinataires"  => ['########'],
		"ftp_serveur"    => '#####',
		"ftp_login"    => '#########',
		"ftp_pw"  => '########',
		"Rep_notices" => '/home/scoopadmin/IN_PERL/Chargements_SUDOC/Notices_delocalisees/',
		"Rep_logs" => '/home/scoopadmin/OUT_PERL/Notices_delocalisees/Logs/',
		"Rep_rapports" => '/home/scoopadmin/OUT_PERL/Notices_delocalisees/Rapports/',
		"Rep_temp" => '/home/scoopadmin/OUT_PERL/Notices_delocalisees/Temp/',		
	);
	return %Config;
}

1;