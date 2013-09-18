#!/usr/bin/perl
#mihael.arcan@yahoo.de
#Jul 2, 2013

use strict;
use warnings;
use Benchmark;
use Data::Dumper;
$Data::Dumper::Useperl = 1;
use Encode qw(encode decode);

use utf8;
binmode(STDIN, ":utf8");
binmode(STDOUT, ":utf8");
my $t0 = new Benchmark;
my $t = time;


	my $domain1 = "gnome";
	my $domain2 = "acquis_tech";

	my $language1 = "en";
	my $language2 = "it";
	
	my $cpus = 6;
	
	my $limit  = 0;
	
	my $corpora_path = "/hltsrv0/arcan/corpus";

	my $out_dir = "/hltsrv0/arcan/dsmmwe_gnome_acq_tech_best_kx_gnome_tm_new2";
	
	#my $moses_conf_d1 = "/hltsrv0/arcan/data/gnome";	
	#my $moses_conf_d2 = "/hltsrv0/arcan/data/acquis";
	
	my $kx_path = "/hltsrv0/arcan/kx_v8.3.3b-german";
	my $moses_bin = "/hltsrv1/software/moses/moses-20130514_irstlm_srilm_xmlrpc_cbtm_cblm_phrasepenalty/bin";
	my $tokenizer = "/hltsrv0/arcan/mosesdecoder/scripts/tokenizer";





my @languages;
push(@languages, $language1, $language2);

my @domains;
push(@domains, $domain1, $domain2);

#make output directory / hash directory for more check-up / tmp for considered files
`mkdir -p $out_dir/$language1\_$language2/smt/$domain1/$t/tmp` unless (-d "$out_dir/$language1\_$language2/smt/$domain1/$t/tmp");
`mkdir -p $out_dir/$language1\_$language2/smt/$domain1/$t/hash` unless (-d "$out_dir/$language1\_$language2/smt/$domain1/$t/hash");
`mkdir -p "$out_dir/tmp/$t/"`;
`mkdir -p "$out_dir/$language1\_$language2/hash_$domain1/$t/"` unless (-d "$out_dir/$language1\_$language2/hash_$domain1/$t/");

open my $considered_files, ">>:utf8", "$out_dir/tmp/$t/considered_files.txt";
 my %files_to_consider;


#reading and copying in-domain data (domain1) for both languages
prepare_data();
sub prepare_data {
	foreach my $i (0 .. $#languages) {
		foreach my $j (0 .. $#domains) {
			#make folders for kx hub
			unless (-d "/hltsrv0/arcan/kx_directory/$languages[$i]_$domains[$j]/hub/") {
				`mkdir -p "/hltsrv0/arcan/kx_directory/$languages[$i]_$domains[$j]/hub/"`;
			}
			#make folders for tokenised files
			unless (-d "/hltsrv0/arcan/tokenized_files/$languages[$i]\_$domains[$j]/") {
				`mkdir -p "/hltsrv0/arcan/tokenized_files/$languages[$i]\_$domains[$j]/"`;
			}
			my $count=0;
			my $path = "$corpora_path/$domains[$j]/$language1\_$language2/$languages[$i]\_$domains[$j]";
			opendir my $folder, "$path" or die "couldn't open $!";
			while (defined (my $filename = readdir($folder))) {
				if (-f "$path/$filename") {
					if (-f "$corpora_path/$domains[$j]/$language1\_$language2/$languages[($i-1)]\_$domains[$j]/$filename") {
						$files_to_consider{$filename}=0;
						#copy files from corpus to kx directory with hub folder
						unless (-f "/hltsrv0/arcan/kx_directory/$languages[$i]\_$domains[$j]/hub/$filename") {
							`cp "$path/$filename" "/hltsrv0/arcan/kx_directory/$languages[$i]\_$domains[$j]/hub/$filename"`;
						}
						#generate tokenized files
						unless (-f "/hltsrv0/arcan/tokenized_files/$languages[$i]\_$domains[$j]/$filename") {
							#`nice $tokenizer/tokenizer.perl -l $languages[$i] -threads $cpus < "$path/$filename" >"/hltsrv0/arcan/tokenized_files/$languages[$i]\_$domains[$j]/$filename"`;
							my $bin="/hltsrv7/MATECAT/code";
							`perl "$bin/monolingual/normalize-character.perl" < "$path/$filename" | "/hltsrv1/software/Python-2.7.2/bin/python" "$bin/monolingual/remove_strange_chars.py" | perl "$bin/monolingual/detokenizer.perl" -b -l "$languages[$i]" | perl  "$bin/monolingual/fix_corpus_opus.pl" -l "$languages[$i]" | perl "$bin/monolingual/fix_corpus_opus-kde.pl" -l "$languages[$i]" | perl "/hltsrv7/MATECAT/code/monolingual/tokenizer.perl" -X -b -l "$languages[$i]" | perl "/hltsrv1/software/moses/moses-20130514_irstlm_srilm_xmlrpc_cbtm_cblm_phrasepenalty/scripts/tokenizer/deescape-special-chars.perl" -b | perl "/hltsrv1/software/moses/moses-20130514_irstlm_srilm_xmlrpc_cbtm_cblm_phrasepenalty/scripts/tokenizer/lowercase.perl" > "/hltsrv0/arcan/tokenized_files/$languages[$i]\_$domains[$j]/$filename"`;
						}
						$count++;
						if (($limit != 0)&&($count == $limit)) {
							last;
						}
					}
				}
			}
		}
	}
	print $considered_files join("\n",keys %files_to_consider);
}



do_giza_alignment();
sub do_giza_alignment {
	#generate giza word alignment files
	foreach my $domain (@domains) {
		my @childs;
		my $num = 0 ;
		`mkdir -p /hltsrv0/arcan/word_alignment/$domain` unless (-d "/hltsrv0/arcan/word_alignment/$domain");
		my $path = "/hltsrv0/arcan/tokenized_files/$language1\_$domain/";
		opendir my $folder, "$path" or die "couldn't open $!";
		while (defined (my $filename = readdir($folder))) {
			if (-f "$path/$filename") {
				if (-f "/hltsrv0/arcan/tokenized_files/$language2\_$domain/$filename") {
					wait() unless ($num < $cpus);
					my $pid = fork();
					if ($pid) {
						push(@childs,$pid);
						$num++;
					} elsif ($pid == 0) {
						giza($filename,$path,$domain);
						exit 0;
					}
					sub giza {
						my $filename = shift;
						my $path = shift;
						my $domain = shift;
						unless (-f "/hltsrv0/arcan/word_alignment/$domain/$filename") {
							print "\tgiza alignment \n";
							my $aligner = `nice bash /hltsrv0/arcan/scripts/Aligner.sh --src "$path/$filename" --trg "/hltsrv0/arcan/tokenized_files/$language2\_$domain/$filename" --gizacfg-src2trg /hltsrv0/arcan/data/acquis_fbk/en_$language2/alignment/$language1-$language2.gizacfg --gizacfg-trg2src /hltsrv0/arcan/data/acquis_fbk/en_$language2/alignment/$language2-$language1.gizacfg --models-iterations m1=1,mh=1,m3=1,m4=3 --sym-type grow`;
							open my $out, ">:utf8", "/hltsrv0/arcan/word_alignment/$domain/$filename" or die "Error/read $!";
							print $out "$aligner";
						}
					}
				}
			}
		}
	}
	while (wait() != -1) {};
}


do_kx_extraction();
sub do_kx_extraction {
	#starting several kx for each language and domain, keyphrase extraction of in/outdomain data
	print " /hltsrv0/arcan/kx_directory/$language1\_$domain1\n";
	my @childs2;
	foreach my $i (1 .. 4) {
		my $pid = fork();
		if ($pid) {
			push(@childs2,$pid);
		
		} elsif ($pid == 0) {
			run_kx($i);
			exit 0;
		}
	}
	sub run_kx {
		my $num = shift;
		`nice perl $kx_path/corpus_analysis/analyze_corpus.perl --param $kx_path/kxparam-user-"$language1-best".pm --dir /hltsrv0/arcan/kx_directory/$language1\_$domain1` if ($num == 1);
		`nice perl $kx_path/corpus_analysis/analyze_corpus.perl --param $kx_path/kxparam-user-"$language1-best".pm --dir /hltsrv0/arcan/kx_directory/$language1\_$domain2` if ($num == 2);
		`nice perl $kx_path/corpus_analysis/analyze_corpus.perl --param $kx_path/kxparam-user-"$language2-best".pm --dir /hltsrv0/arcan/kx_directory/$language2\_$domain1` if ($num == 3);
		`nice perl $kx_path/corpus_analysis/analyze_corpus.perl --param $kx_path/kxparam-user-"$language2-best".pm --dir /hltsrv0/arcan/kx_directory/$language2\_$domain2` if ($num == 4);
	}
	while (wait() != -1) {};
}



my $type = "";
$type = "$languages[0]_$languages[1]_$domain2";
print "intersection_between_languages $type\n";
intersection_between_languages($type);

$type = "$languages[0]_$languages[1]_$domain1";
print "intersection_between_languages $type\n";
intersection_between_languages($type);

sub intersection_between_languages{
	my $type = shift;
	my ($l1, $l2, $d) = $type =~ /^(..)_(..)_(.+?)$/;
	my $folder2 = "$l1\_$d";
	my @childs3;
	my $num = 0 ;
	opendir my $folder, "/hltsrv0/arcan/kx_directory/$folder2/kcn_norm" or die "couldn't open $!";
	while (defined (my $filename = readdir($folder))) {
		
		wait() unless ($num < $cpus);
		my $pid = fork();
		if ($pid) {
			push(@childs3,$pid);
			$num++;
		} elsif ($pid == 0) {
			parallel($filename, "/hltsrv0/arcan", $l1, $l2, $d);
			exit 0;
		}	
		
		sub parallel {
			my $filename = shift;
			my $data_path = shift;
			my $l1 = shift;
			my $l2 = shift;
			my $d  = shift;
	
			my %data;

			my $filetxt = $filename;
			$filetxt =~ s/\.kcn$/\.txt/;
			
			if ((-f "$data_path/kx_directory/$l1\_$d/kcn_norm/$filename")&(exists($files_to_consider{$filetxt}))) {
				if ((-f "$data_path/kx_directory/$l2\_$d/kcn_norm/$filename")) {
					
					print "$filename \n";	
					open my $out_to_translate_l1_d, ">:utf8", "$out_dir/$language1\_$language2/smt/$domain1/$t/tmp/$filename\_translate_$language1\_$d.txt" or die "Error/read $!";
					open my $out_to_translate_l1_d_cfg, ">:utf8", "$out_dir/$language1\_$language2/smt/$domain1/$t/tmp/$filename\_translate_$language1\_$d.cfg" or die "Error/read $!";

					open my $out_to_translate_l2_d, ">:utf8", "$out_dir/$language1\_$language2/smt/$domain1/$t/tmp/$filename\_translate_$language2\_$d.txt" or die "Error/read $!";
					open my $out_to_translate_l2_d_cfg, ">:utf8", "$out_dir/$language1\_$language2/smt/$domain1/$t/tmp/$filename\_translate_$language2\_$d.cfg" or die "Error/read $!";
					
					$filename =~ s/\.kcn//;
					foreach my $x (0 .. 1) {
						open my $kcn_in, "<:utf8", "$data_path/kx_directory/$languages[$x]\_$d/kcn_norm/$filename.kcn" or die "Error/read $!";
						open my $tokenized_file, "<:utf8", "$data_path/tokenized_files/$languages[$x]\_$d/$filename.txt" or die "Error/read $!";
						my $nofl=0;
						my @tokenized;
						my $concat;
						while (my $line = <$tokenized_file>) {
							$concat .= $line;
							chomp($line);
							my @split_sent = split(/\s+/,$line);
							@{$tokenized[$nofl]}=@split_sent;
							$nofl++;
						}
					
						my $j=0;
						while (my $line =<$kcn_in>) {
							chomp($line);
							my ($mwe, $rel);
							
							my @syno_mwes = $line =~ /<(.+?)>/g;
							if (@syno_mwes > 1) {
								($rel) = $line =~ /\> = (.+?) \(.+?\)/;
								foreach my $mwes (@syno_mwes) {
									if ($concat =~ /\b$mwes\b/) {
										$mwe = $mwes;
									}
								}
							} else {
								($mwe, $rel) = $line =~ /\<(.*?)\> = (.+?) \((.+?)\)/;
							}
							
							if  (($mwe)&&($mwe =~ /\w+/)&&(utf8::valid($mwe))) {
								print "$mwe" if ($mwe =~ /\</);
								my $found=0;
								
								my $no_vowels = lc($mwe);
								$no_vowels =~ s/[aeiou\s]//g;
								
								my $line_n;
								foreach my $i (0 .. $#tokenized) {
									my $v = join(" ",  @{$tokenized[$i]});
									if ( $v =~ /\b$mwe\b/i) {
										$found=1;
										$line_n = $i+1;
										last;
									}
								}

								if ($found == 1) {
									if ($languages[$x] eq $language1) {
										print $out_to_translate_l1_d "$mwe\n";
										print $out_to_translate_l1_d_cfg "$d|||$filename|||$languages[$x]|||$mwe|||$line_n\n";
									}
									if ($languages[$x] eq $language2) {
										print $out_to_translate_l2_d "$mwe\n";
										print $out_to_translate_l2_d_cfg "$d|||$filename|||$languages[$x]|||$mwe|||$line_n\n";
									}
									$data{$d}{$filename}{$languages[$x]}{$mwe}{pos}=$j;
									$data{$d}{$filename}{$languages[$x]}{$mwe}{no_vow}=$no_vowels;
									$data{$d}{$filename}{$languages[$x]}{$mwe}{in_line}=$line_n;
									$j++;
								}
							}
						}
						close($kcn_in);
					}
				
					#read alignment file
					open my $alignment_file, "<:utf8", "$data_path/word_alignment/$d/$filename.txt" or die "Error/read $!";
					my %giza;
					my $z=0;
					while (my $line = <$alignment_file>) {
						chomp($line);
						my (@splits) = $line =~ /(\d+-\d+)/g;
						foreach my $a (@splits) {
							my ($src_a, $trg_a) = $a =~ /(\d+)-(\d+)/;
							push(@{$giza{$z}{src_trg}{$src_a}},$trg_a);
							push(@{$giza{$z}{trg_src}{$trg_a}},$src_a);
						}
						$z++;
					}
				
					#read tokenized src and trg files
					open my $token_src, "<:utf8", "$data_path/tokenized_files/$language1\_$d/$filename.txt" or die "Error/read $!";
					open my $token_trg, "<:utf8", "$data_path/tokenized_files/$language2\_$d/$filename.txt" or die "Error/read $!";
					my @token_by_line_src = <$token_src>;
					my @token_by_line_trg = <$token_trg>;
				
					#alignment from src to trg
					foreach my $line (0 .. $#token_by_line_src) {
						if (($token_by_line_src[$line] =~ /[A-z]+/)&&($token_by_line_trg[$line] =~ /[A-z]+/)) {
							foreach my $mwe (sort {$data{$d}{$filename}{$l1}{$a}{pos} <=> $data{$d}{$filename}{$l1}{$b}{pos}} keys %{$data{$d}{$filename}{$l1}}) {
								if ($data{$d}{$filename}{$l1}{$mwe}{in_line} == $line) {
									my $nn = ($data{$d}{$filename}{$l1}{$mwe}{in_line})-1;
									my @split_src = split(/\s/,$token_by_line_src[$nn]);
									my @split_trg = split(/\s/,$token_by_line_trg[$nn]);
									my @split_mwe = split(/\s/,$mwe);
									my $l = @split_mwe;
									my $index = index(lc($token_by_line_src[$nn]),$mwe);
									my $substr = substr($token_by_line_src[$nn],0,($index));
									my @start = split(" ",($substr));
									my $s = @start;		#starting point of src mwe
									my $e = $s + $l -1;	#ending point of src mwe
									if (exists($giza{$nn}{src_trg}{$s})) {
										if ($s != $e) {
											my @arr; 
											my @conti;
											foreach my $src_a ($s .. $e) {
												if (exists($giza{$nn}{src_trg}{$src_a})) {
													foreach my $sca (@{$giza{$nn}{src_trg}{$src_a}}) {
														push(@conti,$sca);
													}
												}
											}
											@conti = sort {$a <=> $b} (@conti);
											foreach my $ea (@conti) {
												push(@arr, $split_trg[$ea]);
											}
											
											#contiguous multi word alignment
											my $start = $conti[0]; my $end = $conti[-1];
											if ($end > $start) {
												my $key_trg = join(" ", @split_trg[$start .. $end]);
												foreach my $mwe_trg (keys %{$data{$d}{$filename}{$l2}}) {
													if (($key_trg =~ /^$mwe_trg$/i)&&($data{$d}{$filename}{$l2}{$mwe_trg}{in_line} == $line)) {
														$data{$d}{$filename}{$l1}{$mwe}{word_alignment_with_kx}=$key_trg;
														last;
													}
												}
												$data{$d}{$filename}{$l1}{$mwe}{word_alignment_contiguous}=($key_trg);
											} else {
												my $key_trg = join(" ", @split_trg[$end .. $start]);
												foreach my $mwe_trg (keys %{$data{$d}{$filename}{$l2}}) {
													if (($key_trg =~ /^$mwe_trg$/i)&&($data{$d}{$filename}{$l2}{$mwe_trg}{in_line} == $line)) {
														$data{$d}{$filename}{$l1}{$mwe}{word_alignment_with_kx}=$key_trg;
														last;
													}
												}
												$data{$d}{$filename}{$l1}{$mwe}{word_alignment_contiguous}=($key_trg);
											}
											
											#non-contiguous multi word alignment
											my $conc .= "$arr[0]";
											foreach my $i (1 .. $#conti) {
												$conc .= " $arr[$i]" if ($arr[$i-1] ne $arr[$i]);
											}
											$data{$d}{$filename}{$l1}{$mwe}{word_alignment}=($conc);
											if ($token_by_line_trg[$nn] =~ /\b\Q$conc\E\b/i) {
												$data{$d}{$filename}{$l1}{$mwe}{word_alignment_in_sentence}=($conc);
											}
											foreach my $mwe_trg (keys %{$data{$d}{$filename}{$l2}}) {
												if (($conc =~ /^$mwe_trg$/i)&&($data{$d}{$filename}{$l2}{$mwe_trg}{in_line} == $line)) {
													$data{$d}{$filename}{$l1}{$mwe}{word_alignment_with_kx}=$conc;
													last;
												}
											}
											
											
										} else {		#one word alignment, but can be aligned to n words
											my $start = $giza{$nn}{src_trg}{$s}[0];
											my $end = $giza{$nn}{src_trg}{$s}[-1];
											my $key_trg;
											if ($start != $end) {
												$key_trg = join(" ", @split_trg[$start .. $end]);
											} else {
												$key_trg = $split_trg[$start];
											}
											$data{$d}{$filename}{$l1}{($mwe)}{word_alignment}=($key_trg);
											$data{$d}{$filename}{$l1}{($mwe)}{word_alignment_contiguous}=($key_trg);
											if ($token_by_line_trg[$nn] =~ /\b\Q$key_trg\E\b/i) {
												$data{$d}{$filename}{$l1}{$mwe}{word_alignment_in_sentence}=($key_trg);
											}
											foreach my $mwe_trg (keys %{$data{$d}{$filename}{$l2}}) {
												if (($key_trg =~ /^$mwe_trg$/i)&&($data{$d}{$filename}{$l2}{$mwe_trg}{in_line} == $line)) {
													$data{$d}{$filename}{$l1}{$mwe}{word_alignment_with_kx}=$key_trg;
													last;
												}
											}
										}
									}
								}
							}
						}
					}
					
					#alignment from $trg to src
					foreach my $line (0 .. $#token_by_line_trg) {
						if (($token_by_line_src[$line] =~ /[A-z]+/)&&($token_by_line_trg[$line] =~ /[A-z]+/)) {
							foreach my $mwe (sort {$data{$d}{$filename}{$l2}{$a}{pos} <=> $data{$d}{$filename}{$l2}{$b}{pos}} keys %{$data{$d}{$filename}{$l2}}) {
								if ($data{$d}{$filename}{$l2}{$mwe}{in_line} == $line) {
									my $nn = ($data{$d}{$filename}{$l2}{$mwe}{in_line})-1;
									my @split_src = split(/\s/,$token_by_line_trg[$nn]); # switch src trg
									my @split_trg = split(/\s/,$token_by_line_src[$nn]); # switch trg src
									my @split_mwe = split(/\s/,$mwe);
									my $l = @split_mwe;
									my $index = index(lc($token_by_line_trg[$nn]),lc($mwe));
									my $substr = substr($token_by_line_trg[$nn],0,($index));
									my @start = split(" ",($substr));
									my $s = @start;
									my $e = $s + $l -1;
									if (exists($giza{$nn}{trg_src}{$s})) {
										if ($s != $e) {
											my @arr; 
											my @conti;
											foreach my $src_a ($s .. $e) {
												if (exists($giza{$nn}{trg_src}{$src_a})) {
													foreach my $sca (@{$giza{$nn}{trg_src}{$src_a}}) {
														push(@conti,$sca);
														
													}
												}
											}
											@conti = sort {$a <=> $b} (@conti);
											foreach my $ea (@conti) {
												push(@arr, $split_trg[$ea]);
											}
											my $start = $conti[0];
											my $end = $conti[-1];
											if ($end > $start) {
												my $key_trg = join(" ", @split_trg[$start..$end]);
												$data{$d}{$filename}{$l2}{($mwe)}{word_alignment_contiguous}=($key_trg);
											} else {
												my $key_trg = join(" ", @split_trg[$end .. $start]);
												$data{$d}{$filename}{$l2}{($mwe)}{word_alignment_contiguous}=($key_trg);
											}
											my $conc .= "$arr[0]";
											foreach my $i (1 .. $#conti) {
												$conc .= " $arr[$i]" if ($arr[$i-1] ne $arr[$i]);
											}
											$data{$d}{$filename}{$l2}{($mwe)}{word_alignment}=($conc);
											if ($token_by_line_src[$nn] =~ /\b\Q$conc\E\b/i) {
												$data{$d}{$filename}{$l2}{($mwe)}{word_alignment_in_sentence}=($conc);
											}
										} else {
											my $start = $giza{$nn}{trg_src}{$s}[0];
											my $end = $giza{$nn}{trg_src}{$s}[-1];
											my $key_trg;
											if ($start != $end) {
												$key_trg = join(" ", @split_trg[$start..$end]);
											} else {
												$key_trg = $split_trg[$start];
											}
											$data{$d}{$filename}{$l2}{($mwe)}{word_alignment}=($key_trg);
											$data{$d}{$filename}{$l2}{($mwe)}{word_alignment_contiguous}=($key_trg);
											if ($token_by_line_src[$nn] =~ /\b\Q$key_trg\E\b/i) {
												$data{$d}{$filename}{$l2}{($mwe)}{word_alignment_in_sentence}=($key_trg);
											}
										}
									}
								}
							}
						}
					}
				
					#generating hash table file
					$Data::Dumper::Purity = 1;
					open my $out_hash, ">:utf8", "$out_dir/$language1\_$language2/hash_$domain1/$t/$filename\_hash.txt";
					print $out_hash Data::Dumper->Dump([\%data], ['*hash']);
					close($out_hash);
					%data = ();
				}
			}
		}
	}
}

while (wait() != -1) {};

#read relevance scores for mwes
my %relevance;
open my $in_relev, "<:utf8", "/hltsrv0/arcan/kx_directory/$language1\_$domain1/lex/key-concepts/kcon_relev.kwe";
while (my $line = <$in_relev>) {
	chomp($line);
	my @syno_mwes = $line =~ /<(.+?)>/g;
	if (@syno_mwes > 1) {
		my ($rel) = $line =~ /\>\s(\d+(\.\d+)?)$/;
		foreach my $mwe (@syno_mwes) {
			if ($mwe && $rel) {
				$relevance{$domain1}{$mwe}=$rel;
			}
		}
	} else {
		my ($mwe, $rel) = $line =~ /\<(.+?)\>\s(\d+(\.\d+)?)$/;
		if ($mwe && $rel) {
			$relevance{$domain1}{$mwe}=$rel;
		}
	}
}
open $in_relev, "<:utf8", "/hltsrv0/arcan/kx_directory/$language1\_$domain2/lex/key-concepts/kcon_relev.kwe";
while (my $line = <$in_relev>) {
	chomp($line);
	my @syno_mwes = $line =~ /<(.+?)>/g;
	if (@syno_mwes > 1) {
		my ($rel) = $line =~ /\>\s(\d+(\.\d+)?)$/;
		foreach my $mwe (@syno_mwes) {
			if ($mwe && $rel) {
				$relevance{$domain2}{$mwe}=$rel;
			}
		}
	} else {
		my ($mwe, $rel) = $line =~ /\<(.+?)\>\s(\d+(\.\d+)?)$/;
		if ($mwe && $rel) {
			$relevance{$domain2}{$mwe}=$rel;
		}
	}
}

#smt part
my $pathtemp = "$out_dir/$language1\_$language2/smt/$domain1/$t/tmp/";
foreach my $d (@domains) {
	opendir my $folder, "$pathtemp" or die "couldn't open $!";
	open my $to_translate_l1, ">:utf8", "$out_dir/$language1\_$language2/smt/$domain1/$t/tr_$language1\_$d.txt" or die "Error/read $!";
	open my $to_translate_l1_cfg, ">:utf8", "$out_dir/$language1\_$language2/smt/$domain1/$t/tr_$language1\_$d.cfg" or die "Error/read $!";

	open my $to_translate_l2, ">:utf8", "$out_dir/$language1\_$language2/smt/$domain1/$t/tr_$language2\_$d.txt" or die "Error/read $!";
	open my $to_translate_l2_cfg, ">:utf8", "$out_dir/$language1\_$language2/smt/$domain1/$t/tr_$language2\_$d.cfg" or die "Error/read $!";

	while (defined (my $filename = readdir($folder))) {
		if ((-f "$pathtemp/$filename")&&($filename =~ /en\_$d\.txt$/)) {
			
			my ($mod_filename) = $filename =~ /^(.+?)_en\_$d\.txt/;
		
			open my $src_txt, "<:utf8", "$pathtemp/$mod_filename\_$language1\_$d.txt";
			open my $src_cfg, "<:utf8", "$pathtemp/$mod_filename\_$language1\_$d.cfg";
			open my $trg_txt, "<:utf8", "$pathtemp/$mod_filename\_$language2\_$d.txt";
			open my $trg_cfg, "<:utf8", "$pathtemp/$mod_filename\_$language2\_$d.cfg";
		
			my @arr_src_txt = <$src_txt>;
			my @arr_src_cfg = <$src_cfg>;
			my @arr_trg_txt = <$trg_txt>;
			my @arr_trg_cfg = <$trg_cfg>;
		
			print $to_translate_l1 join("",@arr_src_txt);
			print $to_translate_l1_cfg join("",@arr_src_cfg);
			print $to_translate_l2 join("",@arr_trg_txt);
			print $to_translate_l2_cfg join("",@arr_trg_cfg);
		
			close($src_txt);close($src_cfg);close($trg_txt);close($trg_cfg);
		
		}
	}
	close($to_translate_l1);close($to_translate_l1_cfg);close($to_translate_l2);close($to_translate_l2_cfg);
}


my %candidates; my %smt; my %possibles;
foreach my $d (@domains) {
	foreach my $k (0 .. $#languages) {
		open my $totranslate, "<:utf8", "$out_dir/$language1\_$language2/smt/$domain1/$t/tr_$languages[$k]\_$d.txt" or die "Error/read $!";
	
		my $n=0;
		while (my $line=<$totranslate>) {
			chomp($line);
			push(@{$candidates{$languages[$k]}{$line}{translate}},$n);
			$n++;
		}
		open my $totranslate_u, ">:utf8", "$out_dir/$language1\_$language2/smt/$domain1/$t/tr_$languages[$k]\_$d.unique" or die $!;
		my $m=0; 
		foreach my $r (keys %{$candidates{$languages[$k]}}) {
			print $totranslate_u "$r\n";
			$candidates{$languages[$k]}{$r}{unique}=$m;
			$m++;
		}
	
		if ($d eq $domain1) {
			print "d1 $d\n";
			#indomain smt model
			`nice -5 $moses_bin/moses -f "/hltsrv0/arcan/data/gnome_corpus/$languages[$k]\_$languages[$k-1]/moses.ini" -v 0 -threads "$cpus" -n-best-list "$out_dir/$language1\_$language2/smt/$domain1/$t/nbestlist_$languages[$k]\_$d.txt" 10 distinct < "$out_dir/$language1\_$language2/smt/$domain1/$t/tr_$languages[$k]\_$d.unique" &> $out_dir/tmp/$t\_smt_out\_$d.stdout`; #-print-alignment-info-in-n-best
		} elsif ($d eq $domain2) {
			#outdomain smt model
			print "d2 $d\n";
			`nice -5 $moses_bin/moses -f "/hltsrv0/arcan/data/acquis_fbk/$languages[$k]\_$languages[$k-1]/moses.ini" -v 0 -threads "$cpus" -n-best-list "$out_dir/$language1\_$language2/smt/$domain1/$t/nbestlist_$languages[$k]\_$d.txt" 10 distinct < "$out_dir/$language1\_$language2/smt/$domain1/$t/tr_$languages[$k]\_$d.unique" &> $out_dir/tmp/$t\_smt_out\_$d.stdout`; #-print-alignment-info-in-n-best
		}
	
		open my $nbest, "<:utf8", "$out_dir/$language1\_$language2/smt/$domain1/$t/nbestlist_$languages[$k]\_$d.txt";
		while (my $line=<$nbest>) {
			chomp($line);
			my ($n, $trans,$p) = $line =~ /^(\d+)\s+\|\|\|\s+(.+?)\s+\|\|\|.+?\|\|\|\s+(.+?)$/;
			if ($n =~ /\d+/) {
				if ($trans) {
					$possibles{$d}{$languages[$k]}{$n}{$trans}=$p;
				} else {
					$possibles{$d}{$languages[$k]}{$n}{"no_translation"}=$p;
				}
			} else {
				print "no n or trans ->  |$line|\n";
			}
		}
	
		my $q=0;
		open my $nbest_cfg, "<:utf8", "$out_dir/$language1\_$language2/smt/$domain1/$t/tr_$languages[$k]\_$d.cfg";
		while (my $line = <$nbest_cfg> ) {
			chomp($line);
			my ($d,$filename,$language, $mwe, $line_n) = $line =~ /^(.+?)\|\|\|(.+?)\|\|\|(.+?)\|\|\|(.+?)\|\|\|(.+?)$/;
			$smt{$d}{$filename}{$languages[$k]}{$mwe}{line}=$line_n; 
			foreach my $poss (sort {$possibles{$d}{$languages[$k]}{$candidates{$languages[$k]}{$mwe}{unique}}{$b} <=> $possibles{$d}{$languages[$k]}{$candidates{$languages[$k]}{$mwe}{unique}}{$a}} keys %{$possibles{$d}{$languages[$k]}{$candidates{$languages[$k]}{$mwe}{unique}}}) {
				push(@{$smt{$d}{$filename}{$languages[$k]}{$mwe}{possibles}},$poss);
			}
			$q++;
		}
	}
}
#print Dumper \%possibles;

#validating if smt output appears in kx-set or in sentence
foreach my $domain (keys %smt) {
	foreach my $filename (keys %{$smt{$domain}}) {
		foreach my $k (0 .. $#languages) {
	
			open my $tokenized_file, "<:utf8", "/hltsrv0/arcan/tokenized_files/$languages[$k-1]\_$domain/$filename.txt" or die "Error/read $!";
			my @file = <$tokenized_file>;
			foreach my $mwe (keys %{$smt{$domain}{$filename}{$languages[$k]}}) {
			
				##!!!!!!!!!!!!!!!!!! why smt should always be one best
				if ($smt{$domain}{$filename}{$languages[$k]}{$mwe}{possibles}[0]) {
					my $best_smt = $smt{$domain}{$filename}{$languages[$k]}{$mwe}{possibles}[0];
					$smt{$domain}{$filename}{$languages[$k]}{$mwe}{smt_aligned_without_checking}=$best_smt;
					if ($file[$smt{$domain}{$filename}{$languages[$k]}{$mwe}{line}-1] =~ /\b\Q$best_smt\E\b/i) {
						$smt{$domain}{$filename}{$languages[$k]}{$mwe}{smt_best_aligned_in_sentence}=$best_smt;
					} else {
					}
					foreach my $i (0 .. $#{$smt{$domain}{$filename}{$languages[$k]}{$mwe}{possibles}}) {
						if ($file[$smt{$domain}{$filename}{$languages[$k]}{$mwe}{line}-1] =~ /\b\Q$smt{$domain}{$filename}{$languages[$k]}{$mwe}{possibles}[$i]\E\b/i) {
							$smt{$domain}{$filename}{$languages[$k]}{$mwe}{smt_n_best_aligned_in_sentence} = $smt{$domain}{$filename}{$languages[$k]}{$mwe}{possibles}[$i];
							last;
						}
					}
				} else {
					
					 print "no smtbest ||| $mwe\n";
				}
			}
			close($tokenized_file);
			#reading the hash table file once
			if ($languages[$k] eq $language1) {
				my %hash;
				open my $db, "<:utf8", "$out_dir/$language1\_$language2/hash_$domain1/$t/$filename\_hash.txt";
				undef $/;
				eval <$db>;
				$/ = "\n";
				close($db);
				foreach my $mwe (keys %{$smt{$domain}{$filename}{$languages[$k]}}) {
					my $best_smt = $smt{$domain}{$filename}{$languages[$k]}{$mwe}{possibles}[0];
					if (exists($hash{$domain}{$filename}{$languages[$k-1]}{$best_smt})||exists($hash{$domain}{$filename}{$languages[$k-1]}{lc($best_smt)})) {
						$smt{$domain}{$filename}{$languages[$k]}{$mwe}{smt_best_aligned_with_kx}=$best_smt;
#						if (($smt{$domain}{$filename}{$languages[$k]}{$mwe}{line} == $hash{$domain}{$filename}{$languages[$k-1]}{($best_smt)}{in_line}) || ($smt{$domain}{$filename}{$languages[$k]}{$mwe}{line} == $hash{$domain}{$filename}{$languages[$k-1]}{lc($best_smt)}{in_line})); #check
					}
					foreach my $i (0 .. $#{$smt{$domain}{$filename}{$languages[$k]}{$mwe}{possibles}}) {
						my $nbest = $smt{$domain}{$filename}{$languages[$k]}{$mwe}{possibles}[$i];
						if ((exists($hash{$domain}{$filename}{$languages[$k-1]}{$nbest})) || (exists($hash{$domain}{$filename}{$languages[$k-1]}{lc($nbest)}))) {
							$smt{$domain}{$filename}{$languages[$k]}{$mwe}{smt_n_best_aligned_with_kx}=$nbest;
#							if (($smt{$domain}{$filename}{$languages[$k]}{$mwe}{line} == $hash{$domain}{$filename}{$languages[$k-1]}{($nbest)}{in_line}) || ($smt{$domain}{$filename}{$languages[$k]}{$mwe}{line} == $hash{$domain}{$filename}{$languages[$k-1]}{lc($nbest)}{in_line})); #check
							
							
							last;
						}
					}
				}
			}
		}
		
		
		#generating smt hash table file
		my %tmphash;
		%{$tmphash{$domain}{$filename}} = %{$smt{$domain}{$filename}};
		$Data::Dumper::Purity = 1;
		open my $out_hash, ">:utf8", "$out_dir/$language1\_$language2/smt/$domain1/$t/hash/$filename\_hash.txt";
		print $out_hash Data::Dumper->Dump([\%tmphash], ['*hash']);
		close($out_hash);
	}
}




my %data; 
foreach my $domain (keys %smt) {
	foreach my $filename (keys %{$smt{$domain}}) {
		foreach my $en_mwe (keys %{$smt{$domain}{$filename}{$language1}}) {
			foreach my $kx_type qw(smt_best_aligned_with_kx smt_n_best_aligned_with_kx) {
				if ($smt{$domain}{$filename}{$language1}{$en_mwe}{$kx_type}) {
					my $src_best = $smt{$domain}{$filename}{$language1}{$en_mwe}{$kx_type};
					$data{$domain}{language_overlap}{$kx_type}{$en_mwe}{$src_best}{i}++;
					$data{$domain}{language_overlap}{$kx_type}{$en_mwe}{$src_best}{rel}=$relevance{$domain}{$en_mwe};
				}
			}
		}
		foreach my $mwe (keys %{$smt{$domain}{$filename}{$language1}}) {
			foreach my $type (keys %{$smt{$domain}{$filename}{$language1}{$mwe}}) {
				if ($type =~ /(smt_n_best_aligned_in_sentence|smt_best_aligned_in_sentence|smt_aligned_without_checking)/) {
					if (exists($smt{$domain}{$filename}{$language1}{$mwe}{$type})) {
						my $src_best = $smt{$domain}{$filename}{$language1}{$mwe}{$type};
						$data{$domain}{language_overlap}{$type}{$mwe}{$src_best}{i}++;
						$data{$domain}{language_overlap}{$type}{$mwe}{$src_best}{rel}=$relevance{$domain}{$mwe};
					}
				}
			}
		}
		foreach my $mwe (keys %{$smt{$domain}{$filename}{$language2}}) {
			foreach my $type (keys %{$smt{$domain}{$filename}{$language2}{$mwe}}) {
				if ($type =~ /(smt_n_best_aligned_in_sentence|smt_best_aligned_in_sentence|smt_aligned_without_checking)/) {
					if (exists($smt{$domain}{$filename}{$language2}{$mwe}{$type})) {
						my $src_best = $smt{$domain}{$filename}{$language2}{$mwe}{$type};
						if ($src_best) {
							$data{$domain}{language_overlap}{$type}{$src_best}{$mwe}{i}++;
							$data{$domain}{language_overlap}{$type}{$src_best}{$mwe}{rel}=$relevance{$domain}{$src_best};
						} else {
#							print "$domain ||| $filename ||| $mwe ||| $type\n"
						}
					}
				}
			}
		}
	}
}


my $path = "$out_dir/$language1\_$language2/hash_$domain1/$t";
opendir my $folder, "$path" or die "couldn't open $!";
while (defined (my $filename = readdir($folder))) {
	if (-f "$path/$filename") {
		#reading the hash table files
		my %hash;
		open my $db, "<:utf8", "$path/$filename";
		undef $/;
		eval <$db>;
		$/ = "\n";
		close($db);
		foreach my $domain (keys %hash) {
			foreach my $filename (keys %{$hash{$domain}}) {
				foreach my $mwe (keys %{$hash{$domain}{$filename}{$language1}}) {
					delete $hash{$domain}{$filename}{$language1}{$mwe}{pos};
					delete $hash{$domain}{$filename}{$language1}{$mwe}{no_vow};
					delete $hash{$domain}{$filename}{$language1}{$mwe}{in_line};
					%{$data{$domain}{$filename}{$language1}{$mwe}} = %{$hash{$domain}{$filename}{$language1}{$mwe}};
				}
				foreach my $mwe (keys %{$hash{$domain}{$filename}{$language2}}) {
					delete $hash{$domain}{$filename}{$language2}{$mwe}{pos};
					delete $hash{$domain}{$filename}{$language2}{$mwe}{no_vow};
					delete $hash{$domain}{$filename}{$language2}{$mwe}{in_line};
					%{$data{$domain}{$filename}{$language2}{$mwe}} =  %{$hash{$domain}{$filename}{$language2}{$mwe}};
				}
				foreach my $en_mwe (keys %{$data{$domain}{$filename}{$language1}}) {
					if ($data{$domain}{$filename}{$language1}{$en_mwe}{word_alignment_with_kx}) {
						my $src_best = $data{$domain}{$filename}{$language1}{$en_mwe}{word_alignment_with_kx};
						$data{$domain}{language_overlap}{word_alignment_with_kx}{$en_mwe}{$src_best}{i}++;
						$data{$domain}{language_overlap}{word_alignment_with_kx}{$en_mwe}{$src_best}{rel}=$relevance{$domain}{$en_mwe};
					}
				}
				foreach my $mwe (keys %{$data{$domain}{$filename}{$language1}}) {
					foreach my $type (keys %{$data{$domain}{$filename}{$language1}{$mwe}}) {
						if (exists($data{$domain}{$filename}{$language1}{$mwe}{$type})) {
							my $src_best = $data{$domain}{$filename}{$language1}{$mwe}{$type};
							$data{$domain}{language_overlap}{$type}{$mwe}{$src_best}{i}++;
							$data{$domain}{language_overlap}{$type}{$mwe}{$src_best}{rel}=$relevance{$domain}{$mwe};
						}
					}
				}
				foreach my $mwe (keys %{$data{$domain}{$filename}{$language2}}) {
					foreach my $type (keys %{$data{$domain}{$filename}{$language2}{$mwe}}) {
						if (exists($data{$domain}{$filename}{$language2}{$mwe}{$type})) {
							my $src_best = $data{$domain}{$filename}{$language2}{$mwe}{$type};
							$data{$domain}{language_overlap}{$type}{$src_best}{$mwe}{i}++;
							$data{$domain}{language_overlap}{$type}{$src_best}{$mwe}{rel}=$relevance{$domain}{$src_best};
						}
					}
				}
			}
		}
	}
}

foreach my $overlap_type (keys %{$data{$domain1}{language_overlap}}) {

	`mkdir -p $out_dir/$language1\_$language2/output/$t/$overlap_type/` unless (-d "$out_dir/$language1\_$language2/output/$t/$overlap_type/");	
	open my $out1, ">:utf8", "$out_dir/$language1\_$language2/output/$t/$overlap_type/dsmmwe_word_alignment_$language1\_$language2\_$domain1\.csv";
	open my $out2, ">:utf8", "$out_dir/$language1\_$language2/output/$t/$overlap_type/dsmmwe_word_alignment\_excluded_due_out_domain_overlap_$language1\_$language2\_$domain1.csv";
	open my $out3a, ">:utf8", "$out_dir/$language1\_$language2/output/$t/$overlap_type/dsmmwe_word_alignment_relevance_consider_$language1\_$language2\_$domain1.csv";
#	open my $out3b, ">:utf8", "$out_dir/$language1\_$language2/output/$t/$overlap_type/dsmmwe_word_alignment_relevance_consider_$language1\_$language2\_$domain1.csv";
	
	foreach my $mwe (keys %{$data{$domain1}{language_overlap}{$overlap_type}}) {
		foreach my $trg (keys %{$data{$domain1}{language_overlap}{$overlap_type}{$mwe}}) {
			if (not exists($data{$domain2}{language_overlap}{$overlap_type}{$mwe}{$trg})) {
				if (($mwe=~ /,/)||($trg=~/,/)) {
					print $out1 "\"$mwe ||| $trg\", $data{$domain1}{language_overlap}{$overlap_type}{$mwe}{$trg}{i} \n";
				} else {
					print $out1 "$mwe ||| $trg, $data{$domain1}{language_overlap}{$overlap_type}{$mwe}{$trg}{i} \n";
				}
			} elsif ($relevance{$domain1}{$mwe} && $relevance{$domain2}{$mwe} && ($relevance{$domain1}{$mwe} > $relevance{$domain2}{$mwe})) {
				print $out3a "\"$mwe ||| $trg\", $data{$domain1}{language_overlap}{$overlap_type}{$mwe}{$trg}{i} \n";
#				print $out3b "\"$mwe ||| $trg\", $data{$domain1}{language_overlap}{$overlap_type}{$mwe}{$trg}{i} \n";
			} else {
				if (($mwe=~ /,/)||($trg=~/,/)) {
					print $out2 "\"$mwe ||| $trg\", $data{$domain1}{language_overlap}{$overlap_type}{$mwe}{$trg}{i} \n";
				} else {
					print $out2 "$mwe ||| $trg, $data{$domain1}{language_overlap}{$overlap_type}{$mwe}{$trg}{i} \n";
				}
			}
		}
	}
}

while (wait() != -1) {};
#-----------------------------------------
print "\n--------------------\nthe code took: ", timestr(timediff(new Benchmark, $t0)), "\n";
