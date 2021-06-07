package Notice;    # Nom du package, de notre classe
use warnings;        # Avertissement des messages d'erreurs
use strict;          # Vérification des déclarations
use Carp;            # Utile pour émettre certains avertissements
use utf8;
use MarcEncode;

my %type_notice  = ( 
	'aa' => 'Partie composante d\'imprimé (As)',
	'ac' => 'Recueil factice d\'imprimés (Ar)',
	'am' => 'Monographie imprimée (Aa)',
	'as' => 'Périodique imprimé (Ab)',
	'as' => 'Périodique imprimé (Ab)',
	'bm' => 'Manuscrit (Fa)',
	'cm' => 'Partition imprimée (Ma)',
	'cs' => 'Collection de partitions imprimées (Md)',
	'dm' => 'Partition manuscrite (La)',
	'em' => 'Carte imprimée (Ka)',
	'es' => 'Collection de cartes imprimées (Kd)',
	'fm' => 'Carte manuscrite (Pa)',
	'ga' => 'Extrait de document audiovisuel (Bs)',
	'gc' => 'Recueil factice de documents audiovisuels (Br)',
	'gm' => 'Document audiovisuel (Ba)',
	'gs' => 'Périodique sous forme de documents audiovisuels (Bb)',
	'gs' => 'Collection de documents audiovisuels (Bd)',
	'im' => 'Enregistrement sonore non musical (Na)',
	'is' => 'Périodique sous forme d\'enregistrements sonores non musicaux (Nb)',
	'is' => 'Collection d\'enregistrements sonores non musicaux (Nd)',
	'jm' => 'Enregistrement sonore musical (Ga)',
	'js' => 'Collection d\'enregistrements sonores musicaux (Gd)',
	'km' => 'Image fixe (Ia)',
	'lc' => 'Recueil factice de documents électroniques (Or)',
	'lm' => 'Document électronique ou partie de document électronique (Oa ou Os)',
	'ls' => 'Périodique électronique ou collection de documents électroniques (Ob ou Od)',
	'mc' => 'Recueil factice de documents multimédias multisupports (Zr)',
	'mm' => 'Document multimédia multisupport (Za)',
	'ms' => 'Périodique multimédia multisupport (Zb)',
	'ms' => 'Collection de documents multimédias multisupports (Zd)',
	'rm' => 'Objet (Va)',
  ); 
my %genre_litteraire = (
	'a' => 'Fiction, roman',
	'b' => 'Théâtre',
	'f' => 'Nouvelles',
	'g' => 'Poésie',
	'z' => 	'Formes variées ou autres formes littéraire'
	);
sub new {
  my ( $classe, $notice ) = @_;

  	# Vérifions la classe
	$classe = ref($classe) || $classe;

 	# Création de la référence anonyme d'un hachage vide (futur objet)
	my $this = {};
	# Liaison de l'objet à la classe
  	bless( $this, $classe );
  	$notice->encoding( 'UTF-8' );
	$this->{PPN} = $notice->field('001')->data();
	
	my $titre = $notice->subfield('200',"a") ? $notice->subfield('200',"a") : "Null";
	$titre =~ s/\x88//gm;
	$titre =~ s/\x89//gm;
	$titre = ($notice->subfield('200',"e")) ? $titre." : ".$notice->subfield('200',"e") : $titre;
	carp "Titre non renseigné pour le PPN $this->{PPN} !" if (!$titre);
	$this->{TITRE}     = MarcEncode::char_encode($titre);
	$this->{ISBN}      = $notice->subfield('010',"a") ? $notice->subfield('010',"a") : "Null" ;
	$this->{ISSN}      = $notice->subfield('011',"a")  ? $notice->subfield('011',"a") : "Null";
	$this->{TYPE_NOTICE} = $type_notice{substr($notice->leader(),6,2)};
	$this->{LOCALISATION} = recup_loc($notice);
#	$this->{EDITEUR} = ;
#	$this->{DATE_PUB} = ;
	$this->{a_statut_chargement} = controle_notice_filtree($notice);
	$this->{c_pb_transl} = controle_pb_transl($notice);
	$this->{d_200_b} = controle_200b($notice);
	$this->{e_181_182} = controle_181182($notice);
	$this->{f_date_pub} = controle_date_pub($notice);
	$this->{g_collection} = controle_collection($notice);
	$this->{h_autorites} = controle_autorites($notice);
	($this->{i_auteurs},$this->{j_resp}) = controle_auteurs($notice);
	$this->{k_453} = controle_453($notice);
	$this->{l_488} = controle_488($notice);
	return $this;
}


####################################################
#Fonctions de contrôle des notices bibliographiques#
####################################################

#Regarde si la notice a été filtrée au chargement dans horizon
#Règles de filtrages
#label -->000/07 = s et 000/08 = 1
#label -->000/07 = c
#label -->000/05 = d
#100	  -->Zone absente		
#110	  -->110$a/01 = b
sub recup_loc{
	my $notice = shift;
	my %date_modif;
	foreach my $champs ($notice->field(930)) {
	$date_modif{$champs->subfield("b")} = 1; 
	}
return \%date_modif;
	
}
sub controle_notice_filtree{
	my $notice = shift;
	my %regles_filtrages = (
		a_chapeau => {
			controle => sub{substr($_[0]->leader(),7,1) eq 's' && substr($_[0]->leader(),8,1) == 1 },
			raison => "Notice mère de publication en série"
		},
		b_collection => {
			controle => sub{substr($_[0]->leader(),7,1) eq 'c'},
			raison => "Notice de collection"			
		},
		c_suppression => {
			controle => sub{substr($_[0]->leader(),5,1) eq 'd'},
			raison => "Notice détruite"			
		},
		d_absent_chmp100 => {
			controle => sub{! $_[0]->field('100')},
			raison => "Champs 100 absent"			
		},
		e_collection_chmp110 => {
			controle => sub{if($_[0]->subfield('110',"a")){substr($_[0]->subfield('110',"a"),0,1) eq 'b'}},
			raison => "Notice de collection"			
		},			
	);
	foreach my $regle (sort keys %regles_filtrages){
		if ($regles_filtrages{$regle}{controle}->($notice)){
			return ['Notice filtrée : ' . $regles_filtrages{$regle}{raison},1];
		}	
	}
	return [" ",0];
}

#Si pas de titre problème de zone 104
sub controle_pb_transl{
	my $notice = shift;
	my @result = ('',0);
	if (! $notice->subfield('200',"a")){
		@result = ('Absence de champs 200 problème de translitéartion (pas de champs 104 ou $7 mal renseigné) supposé.',1);
	}
	return \@result;
}


#Teste la présence du sous-champs 200$b et des champs 181 et 182. Si les trois sont absents retourne une erreur
sub controle_200b{
	my $notice = shift;
	my @result = ('',0);
	unless ($notice->subfield('200',"b")){
		unless ($notice->field('181')){
			return ['Type de support non renseigné (pas de 200$b ou pas de 181/182)',1];			
		}
	}
	return \@result;
}

#Teste la présence des champs 181 & 182
sub controle_181182{
	my $notice = shift;
	if ($notice->field('181') or $notice->field('182')){
		if (! $notice->field('183')){
			return ['Pas de 183',1];
		}
		else {
			return ['',0];
		}
	}
	return ['Pas de 181/182',2]
}

#Controle sur la date de publication : regarde si la date de la zone de données codées correspond à la date de la 200$d
sub controle_date_pub {
	my $notice = shift;
	my $ppn = $notice->field('001')->data();
	if (! $notice->subfield('100',"a")){
		return ["La zone 100 n'est pas renseignée",1];
	}
	my $date_100 = ($notice->subfield('100',"a"))?substr($notice->subfield('100',"a"),9,4):"Abst";
	my $alphabet = ($notice->subfield('100',"a"))?substr($notice->subfield('100',"a"),34,2):"ba";
#	print "$date_100 vs $date_210d \n";
	if (my $date_210d = $notice->subfield('210',"d")){
		my $date_err = $date_210d;
		$date_210d =~ s/,.*$//;
		my $date_210 = "";
#		Test notices translitérés
		if ($alphabet ne 'ba'){
			$date_210d =~ m/(\[.*?\])/;
			$date_210 = $1;
			if (!$date_210){
				$date_210d =~ m/([0-9]{2,4})/;
				$date_210 = $1;
			}
		}
		else {
			$date_210d =~ m/([0-9]{2,4})/;
			$date_210 = $1;
		}
		$date_210 = "Date 210 non renseignée ou non identifiable : $date_err" if (! $date_210);
		if ($date_100 ne $date_210){
			return ["Dates divergentes ($date_100 vs $date_210)",1];
		}
		return ["",0];
	}
	elsif (my $date_210h = $notice->subfield('210',"h")){
		$date_210h =~ s/,.*$//;
		$date_210h =~ m/([0-9]{2,4})/;
		my $date_210 = $1;
		if ($date_100 ne $date_210){
			return ["Dates divergentes ($date_100 vs $date_210)",1];
		}
		return ["",0];
	}
	else{
		if ($date_100 <= 1810){
			if (! $notice->field('210')){
				return ["Livre ancien champs 210 Absent",1];
			}
			return ["Livre ancien non applicable",1];
		}
		return ["210\$d Absent",1];
	}
}

#S'il y a un champs 225 un champs 410 doit être créé
sub controle_collection{ 
	my $notice = shift;
	if ($notice->field('225')){
		unless ( $notice->field('410') || $notice->field('461')){
			return ["410 ou 461 Absente",1];
		}
		elsif ( $notice->field('410')){
			return ["La notice de collection n'a pas été liéee à la notice du document",2] unless $notice->subfield('410',"0");
		}
		elsif ( $notice->field('461') && substr($notice->leader(),6,2) eq 'as'){
			return ["La notice de collection n'a pas été liéee à la notice du document",2] unless $notice->subfield('410',"0");
		} 
	}
	return ["",0];
}

#Controle les autorités et s'assure de la présence d'un \$3
#Renvoi Error si au moins un 60# avec un $2 rameau n'a pas de $3 (lien vers l'autorité)
#Renvoi 0 si aucun champs 60#  avec un $2 rameau n'est présent
#Renvoi un nombre positif si tout est ok 
sub controle_autorites{
	my $notice = shift;
	if ($notice->subfield('105',"a")){
		if (my $genre = substr($notice->subfield('105',"a"),11,1)){	
			if (exists $genre_litteraire{$genre}){
				return [$genre_litteraire{$genre},0];	
			}
	}
	}
	my @liste_champs_matiere = (600,601,602,604,605,606,607,609);
	my $nb_rameau = 0;
	#Pour chaque champs sujet
	foreach my $i (@liste_champs_matiere) {
		#Je charge mon champs
   		foreach my $champs ($notice->field($i)) {
#   			print "\t\t--",$i," : ", $champs->subfield("a"), "\n";
   			#Si un $2 Rameau existe
   			if( $champs->subfield("2") eq 'rameau' ){
   				$nb_rameau ++;
   				#Et n'a pas de $3 on retourne une erreur
   				if (! $champs->subfield("3")){
   					return ["Au moins une autorité Rameau sans \$3", 1];
   				}
   			}
   		}

   }
   #On compte le nombre de champs avec un $2rameau si <>0 c'est une erreur
   if ($nb_rameau == 0){
   	return ["Pas d'autorité Rameau", 1];
   	}
   return ["",0];
}

#Controle les autorités auteur et s'assure de la présence d'un \$3
sub controle_auteurs{	
		my $notice = shift;
		my $lien_idref = ["",0];
		my $resp = ["",0];
		my @liste_champs_auteur = (700,701,702,710,711,712,716,720,721,722);
		foreach my $i (@liste_champs_auteur) {
#			print "$i\n";
    		foreach my $champs ($notice->field($i)) {
#    			print "\t\t--",$i," : ", $champs->subfield("a"), "\n";
    				if (! $champs->subfield("3")){
    					$lien_idref =  ["Au moins une autorité non liée à Idref",1]; 
    				}
    				if (! $champs->subfield("4")){
    					$resp =  ["Au moins une autorité sans mention de responsabilité",1];
    				}
    		}
    }
    return ($lien_idref,$resp);
}


sub controle_453{
	my $notice = shift;
	my $message = ["",0];
	return $message if substr($notice->leader(),6,2) ne "aa";
	return $message unless $notice->field('453');
	foreach my $champs_453 ($notice->field('453')) {
		return 	["Champs 453 avec un lien $0 pour une notice de monographie",1] if $champs_453->subfield("0");
	}
	return $message;
}

sub controle_488{
	my $notice = shift;
	my $message = ["",0];
	if ($notice->field('488')) {
		return 	["Champs 488 sans champs 311",1] unless $notice->field('311');
	}
	return $message;
}
1;                # Important, à ne pas oublier
__END__           # Le compilateur ne lira pas les lignes après elle
