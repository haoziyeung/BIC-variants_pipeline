#!/usr/bin/perl

use strict;
use Getopt::Long qw(GetOptions);
use FindBin qw($Bin); 

use lib "$Bin/lib";
use Schedule;
use Cluster;
use File::Basename;


my ($pair, $patient, $group, $bamgroup, $config, $nosnps, $targets, $ug, $scheduler, $priority_project, $priority_group, $abra, $help, $step1, $allSomatic, $scalpel, $somaticsniper, $strelka, $varscan, $virmid);

my $pre = 'TEMP';
my $output = "results";
my $species = 'mm10';

my $uID = `/usr/bin/id -u -n`;
chomp $uID;
my $rsync = "/ifs/solres/$uID";

GetOptions ('pre=s' => \$pre,
	    'pair=s' => \$pair,
	    'patient=s' => \$patient,
            'group=s' => \$group,
	    'config=s' => \$config,
	    'targets=s' => \$targets,
	    'species=s' => \$species,
	    'nosnps' => \$nosnps,
	    'step1' => \$step1,
	    'ug|unifiedgenotyper' => \$ug,
	    'abra' => \$abra,
	    'bamgroup=s' => \$bamgroup,
 	    'scheduler=s' => \$scheduler,
 	    'priority_project=s' => \$priority_project,
 	    'priority_group=s' => \$priority_group,
	    'help' => \$help,
	    'rsync=s' => \$rsync,
	    'allsomatic|allSomatic|all_somatic' => \$allSomatic,
	    'scalpel' => \$scalpel,
	    'somaticsniper' => \$somaticsniper,
	    'strelka' => \$strelka,
	    'varscan' => \$varscan,
	    'virmid' => \$virmid,
 	    'output|out|o=s' => \$output) or exit(1);


if(!$group || !$config || !$scheduler || !$targets || !$bamgroup || $help){
    print <<HELP;

    USAGE: process_alignments_hg19.pl -group GROUP -pair PAIR -pre PRE -config CONFIG -species SPECIES -scheduler SCHEDULER -targets TARGETS
	* GROUP: file listing grouping of samples for realign/recal steps (REQUIRED)
	* BAMGROUP: files listing bams to be processed together; every bam for each group on 1 line, comma-separated (required)
	* TARGETS: name of targets assay; will search for targets/baits ilists and targets padded file in $Bin/targets/TARGETS unless given full path to targets directory (REQUIRED)
	* CONFIG: file listing paths to programs needed for pipeline; full path to config file needed (REQUIRED)
	* SCHEDULER: currently support for SGE and LSF (REQUIRED)
	* PAIR: file listing tumor/normal pairing of samples for mutect/maf conversion; if not specified, considered unpaired
	* PRE: output prefix (default: TEMP)
	* SPECIES: mm10 (default), mm10_custom, and mm9
	* OUTPUT: output results directory (default: results)
	* RSYNC:  path to rsync data for archive (default: /ifs/solres/USER_ID)
	* PRIORITY_PROJECT: sge notion of priority assigned to projects (default: ngs)
	* PRIORITY_GROUP: lsf notion of priority assigned to groups (default: Pipeline)
	* -nosnps: if no snps to be called; e.g. when only indelrealigned/recalibrated bams needed
	* -abra: run abra instead of GATK indelrealigner
	* -step1: forece the pipeline to start from the first step in pipeline
	* haplotypecaller is default; -ug || -unifiedgenotyper to also make unifiedgenotyper variant calls	
	* ALLSOMATIC: run all somatic callers; mutect/haplotypecaller always run; otherwise -scalpel, -somaticsniper, -strelka, -varscan, -virmid to run them individually	
HELP
exit;
}

my $curDir = `pwd`;
chomp $curDir;
if($output !~ /^\//){
    $output = "$curDir/$output";
}

if($pre =~ /^\d+/){
    $pre = "s_$pre";
}

my $ABRA = '';
my $BCFTOOLS = '';
my $GATK = '';
my $PICARD = '';
my $FACETS_LIB = '';
my $FACETS_SUITE = '';
my $MUTECT = '';
my $SAMTOOLS = '';
my $SOMATIC_SNIPER = '';
my $VARSCAN = '';
my $STRELKA = '';
my $SCALPEL = '';
my $TABIX = '';
my $VIRMID = '';
my $JAVA = '';
my $PYTHON = '';
my $PERL = '';
my $MM9_FASTA = '';
my $MM9_BWA_INDEX = '';
my $MM10_FASTA = '';
my $MM10_BWA_INDEX = '';
my $MM10_CUSTOM_FASTA = '';
my $MM10_CUSTOM_BWA_INDEX = '';
my $REF_SEQ = '';

open(CONFIG, "$config") or die "CAN'T OPEN CONFIG FILE $config";
while(<CONFIG>){
    chomp;

    my @conf = split(/\s+/, $_);
    if($conf[0] =~ /abra/i){
	if(!-e "$conf[1]/abra.jar"){
	    die "CAN'T FIND GenomeAnalysisTK.jar IN $conf[1] $!";
	}
	$ABRA = $conf[1];
    }
    elsif($conf[0] =~ /gatk/i){
	if(!-e "$conf[1]/GenomeAnalysisTK.jar"){
	    die "CAN'T FIND GenomeAnalysisTK.jar IN $conf[1] $!";
	}
	$GATK = $conf[1];
    }
    elsif($conf[0] =~ /tabix/i){
        if(!-e "$conf[1]/bgzip"){
            die "CAN'T FIND tabix IN $conf[1] $!";
        }
        $TABIX = $conf[1];
    }
    elsif($conf[0] =~ /bcftools/i){
        if(!-e "$conf[1]/bcftools"){
            die "CAN'T FIND bcftools IN $conf[1] $!";
        }
        $BCFTOOLS = $conf[1];
    }
    elsif($conf[0] =~ /mutect/i){
	if(!-e "$conf[1]/muTect.jar"){
	    die "CAN'T FIND muTect.jar IN $conf[1] $!";
	}
	$MUTECT = $conf[1];
    }
    elsif($conf[0] =~ /facets_suite/i){
        if(!-e "$conf[1]/facets"){
            die "CAN'T FIND facets_suite IN $conf[1] $!";
        }
        $FACETS_SUITE = $conf[1];
    }
    elsif($conf[0] =~ /facets_lib/i){
        if(!-e "$conf[1]/facets"){
            die "CAN'T FIND facets_lib IN $conf[1] $!";
        }
        $FACETS_LIB = $conf[1];
    }
    elsif($conf[0] =~ /picard/i){
	if(!-e "$conf[1]/picard.jar"){
	    die "CAN'T FIND picard.jar IN $conf[1] $!";
	}
	$PICARD = $conf[1];
    }
    elsif($conf[0] =~ /samtools/i){
	if(!-e "$conf[1]/samtools"){
	    die "CAN'T FIND samtools IN $conf[1] $!";
	}
	$SAMTOOLS = $conf[1];
    }
    elsif($conf[0] =~ /somaticsniper/i){
	if(!-e "$conf[1]/bam-somaticsniper"){
	    die "CAN'T FIND bam-somaticsniper IN $conf[1] $!";
	}
	$SOMATIC_SNIPER = $conf[1];
    }
    elsif($conf[0] =~ /varscan/i){
	if(!-e "$conf[1]/VarScan.jar"){
	    die "CAN'T FIND VarScan.jar IN $conf[1] $!";
	}
	$VARSCAN = $conf[1];
    }
    elsif($conf[0] =~ /strelka/i){
	if(!-e "$conf[1]/bin/configureStrelkaWorkflow.pl"){
	    die "CAN'T FIND bin/configureStrelkaWorkflow.pl IN $conf[1] $!";
	}
	$STRELKA = $conf[1];
    }
    elsif($conf[0] =~ /scalpel/i){
	if(!-e "$conf[1]/scalpel"){
	    die "CAN'T FIND scalpel IN $conf[1] $!";
	}
	$SCALPEL = $conf[1];
    }
    elsif($conf[0] =~ /virmid/i){
	if(!-e "$conf[1]/Virmid.jar"){
	    die "CAN'T FIND Virmid.jar IN $conf[1] $!";
	}
	$VIRMID = $conf[1];
    }
    elsif($conf[0] =~ /java/i){
	if(!-e "$conf[1]/java"){
	    die "CAN'T FIND java IN $conf[1] $!";
	}
	$JAVA = $conf[1];
    }
    elsif($conf[0] =~ /perl/i){
	if(!-e "$conf[1]/perl"){
	    die "CAN'T FIND perl IN $conf[1] $!";
	}
	$PERL = $conf[1];
    }
    elsif($conf[0] =~ /python/i){
	if(!-e "$conf[1]/python"){
	    die "CAN'T FIND python IN $conf[1] $!";
	}
	$PYTHON = $conf[1];
    }
     elsif($conf[0] =~ /^r$/i){
	if(!-e "$conf[1]/R"){
	    die "CAN'T FIND R IN $conf[1] $!";
	}
	my $path_tmp = $ENV{'PATH'};
	$ENV{'PATH'} = "$conf[1]:$path_tmp";
    }
   elsif($conf[0] =~ /mm9_fasta/i){
	if(!-e "$conf[1]"){
	    if($species =~ /mm9/i){
		die "CAN'T FIND $conf[1] $!";
	    }
	}
	$MM9_FASTA = $conf[1];
    }
    elsif($conf[0] =~ /mm9_bwa_index/i){
	if(!-e "$conf[1]\.bwt" || !-e "$conf[1]\.pac" || !-e "$conf[1]\.ann" || !-e "$conf[1]\.amb" || !-e "$conf[1]\.sa"){
	    if($species =~ /mm9/i){
		die "CAN'T FIND ALL NECESSARY BWA INDEX FILES FOR MM9 WITH PREFIX $conf[1] $!";
	    }
	}
	$MM9_BWA_INDEX = $conf[1];
    }
    elsif($conf[0] =~ /mm10_fasta/i){
	if(!-e "$conf[1]"){
	    if($species =~ /^mm10$/i){
		die "CAN'T FIND $conf[1] $!";
	    }
	}
	$MM10_FASTA = $conf[1];
    }
    elsif($conf[0] =~ /mm10_bwa_index/i){
	if(!-e "$conf[1]\.bwt" || !-e "$conf[1]\.pac" || !-e "$conf[1]\.ann" || !-e "$conf[1]\.amb" || !-e "$conf[1]\.sa"){
	    if($species =~ /^mm10$/i){
		die "CAN'T FIND ALL NECESSARY BWA INDEX FILES FOR MM10 WITH PREFIX $conf[1] $!";
	    }
	}
	$MM10_BWA_INDEX = $conf[1];
    }
    elsif($conf[0] =~ /mm10_custom_fasta/i){
	if(!-e "$conf[1]"){
	    if($species =~ /mm10_custom/i){
		die "CAN'T FIND $conf[1] $!";
	    }
	}
	$MM10_CUSTOM_FASTA = $conf[1];
    }
    elsif($conf[0] =~ /mm10_bwa_index/i){
	if(!-e "$conf[1]\.bwt" || !-e "$conf[1]\.pac" || !-e "$conf[1]\.ann" || !-e "$conf[1]\.amb" || !-e "$conf[1]\.sa"){
	    if($species =~ /mm10_custom/i){
		die "CAN'T FIND ALL NECESSARY BWA INDEX FILES FOR MM10_CUSTOM WITH PREFIX $conf[1] $!";
	    }
	}
	$MM10_CUSTOM_BWA_INDEX = $conf[1];
    }
}
close CONFIG;

my $REF_SEQ = "$MM10_FASTA";
my $BWA_INDEX = "$MM10_BWA_INDEX";
my $DB_SNP = "$Bin/data/mm10/mm10_snp142.vcf";
my $ABRA_TARGETS = "$Bin/targets/abra/abra_target_regions_mm10.bed";
my $CHR_M = 'M'; #as of right now default to M. Once we add NCBI assemblies, we can chang it below.
my $CHR_PREFIX = "chr"; #as of right now default to 'chr'. Once we add NCBI assemblies, we can chang it below.

if($species =~ /mm10_custom/i){
    $REF_SEQ = "$MM10_CUSTOM_FASTA";
    $BWA_INDEX = "$MM10_CUSTOM_BWA_INDEX";
}
elsif($species =~ /mm9/i){
    $REF_SEQ = "$MM9_FASTA";
    $BWA_INDEX = "$MM9_BWA_INDEX";
    $DB_SNP = "";
    $ABRA_TARGETS = '';
}

### make sure all markdup bam files are there before proceeding
open(BGR, "$bamgroup") || die "CAN'T OPEN GROUPING FILE OF MARKDUP BAMS $bamgroup $!";
while(<BGR>){
    chomp;

    my @bgro = split(/\s+/, $_);
    my @bgr = split(/,/, $bgro[1]);
    foreach my $bg (@bgr){
	if(!-e $bg){
	    die "file $bg does not exist";
	}
    }
}
close BGR;

my $targets_bed_padded = "$Bin/targets/$targets/$targets\_targets_plus5bp.bed";
if(-d $targets){
    my @path = split(/\//, $targets);
    my $assay = pop @path;
    $targets_bed_padded = "$targets/$assay\_targets_plus5bp.bed";
}

if(!-e "$targets_bed_padded"){
    die "CAN'T LOCATE $targets_bed_padded FOR $targets; REQUIRED FOR SCALPEL $!";
}

my $multipleTargets = '';

###if($target){
###   if(!-e $target){
###	die "target file $target cannot be found $!";
###    }
###    $multipleTargets = "-L $target_bed --interval_set_rule INTERSECTION";
###}


my $count = 0;
my %inputFiles = ();
my @processedBams = ();
my @finalBams = ();
my $ran_pr_glob = 0;
my @prg_jids = ();
my $ran_ssf = 0;
my @ssf_jids = ();
my @all_jids = ();

`/bin/mkdir -m 775 -p $output`;
`/bin/mkdir -m 775 -p $output/intFiles`;
`/bin/mkdir -m 775 -p $output/alignments`;
`/bin/mkdir -m 775 -p $output/progress`;

my %addParams = (scheduler => "$scheduler", runtime => "500", priority_project=> "$priority_project", priority_group=> "$priority_group", queues => "lau.q,lcg.q,nce.q", rerun => "1", iounits => "1");
my $additionalParams = Schedule::additionalParams(%addParams);

open(IN, "$bamgroup") || die "CAN'T OPEN GROUPING FILE OF MARKDUP BAMS $bamgroup $!";
while(<IN>){
    chomp;
    
    my @gpair = split(/\s+/, $_);
    my @pair = split(/,/, $gpair[1]);
    my @pins = ();
    foreach my $pai (@pair){
	my @sn = split(/\//, $pai);
	if($inputFiles{$pai}){
	    next;
	}
	push @pins, "-I $pai";
	$inputFiles{$pai} = 1;
        
        my $samp = $sn[-3];
        push @finalBams, "$output/alignments/$pre\_indelRealigned_recal_$samp.bam";
    }

    if(scalar(@pins) == 0){
	next;
    }

    my $bgroup = join(" ", @pins);
    my @indelBams = ();
    my $ran_ir == 0;
    my @ir_jids = ();

    if($abra){
	my @inBams = ();
	my @outBams = ();
	foreach my $pin (@pins){
	    my @inB = split(/\s+/, $pin);
	    push @inBams, $inB[1];
	    push @outBams, "$inB[1]\_ABRA.bam";
	    push @indelBams, "-I $inB[1]\_ABRA.bam\_FM.bam";
	}
	
	my $aiBams = join(",", @inBams);
	my $aoBams = join(",", @outBams);
	my $ran_abra = 0;
	my $abraj = '';
	if(!-e "$output/progress/$pre\_$uID\_$gpair[0]\_ABRA.done" || $step1){
	    my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$gpair[0]\_ABRA", cpu => "12", mem => "90", cluster_out => "$output/progress/$pre\_$uID\_$gpair[0]\_ABRA.log");
	    my $standardParams = Schedule::queuing(%stdParams);	    
	    my %addParams = (scheduler => "$scheduler", runtime => "500", priority_project=> "$priority_project", priority_group=> "$priority_group", rerun => "1", iounits => "4");
	    my $additionalParams = Schedule::additionalParams(%addParams);
	    `$standardParams->{submit} $standardParams->{job_name} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $PERL/perl $Bin/abra_wrapper.pl -inBams $aiBams -outBams $aoBams -refSeq $REF_SEQ -bwaRef $BWA_INDEX -targets $ABRA_TARGETS -working $output/intFiles/abra_$gpair[0] -config $config -log $output/progress/$pre\_$uID\_$gpair[0]\_ABRA_WRAPPER.log`;

	    $abraj = "$pre\_$uID\_$gpair[0]\_ABRA";
	    `/bin/touch $output/progress/$pre\_$uID\_$gpair[0]\_ABRA.done`;
	    $ran_abra = 1;
	}

	if(!-e "$output/progress/$pre\_$uID\_$gpair[0]\_FIXMATE.done" || $ran_abra){
	    sleep(2);
	    my $bcount = 0;
	    foreach my $outBam (@outBams){
		$bcount++;
		my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$gpair[0]\_$bcount\_FIXMATE", job_hold => "$abraj", cpu => "1", mem => "50", cluster_out => "$output/progress/$pre\_$uID\_$gpair[0]\_$bcount\_FIXMATE.log");
		my $standardParams = Schedule::queuing(%stdParams);
		my %addParams = (scheduler => "$scheduler", runtime => "500", priority_project=> "$priority_project", priority_group=> "$priority_group", queues => "lau.q,lcg.q,nce.q", rerun => "1", iounits => "5");
		my $additionalParams = Schedule::additionalParams(%addParams);

		`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $JAVA/java -Xms256m -Xmx50g -XX:-UseGCOverheadLimit -Djava.io.tmpdir=/scratch/$uID -jar $PICARD/picard.jar FixMateInformation I=$outBam O=$outBam\_FM.bam SORT_ORDER=coordinate VALIDATION_STRINGENCY=LENIENT TMP_DIR=/scratch/$uID MAX_RECORDS_IN_RAM=5000000 CREATE_INDEX=true`;
		push @ir_jids, "$pre\_$uID\_$gpair[0]\_$bcount\_FIXMATE";
	    }
	    `/bin/touch $output/progress/$pre\_$uID\_$gpair[0]\_FIXMATE.done`;
	    $ran_ir = 1;
	}
    }
    else{
	my $ran_rtc = 0;
	my $rtc_jid = '';
	if(!-e "$output/progress/$pre\_$uID\_$gpair[0]\_RTC.done" || $step1){
	    my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$gpair[0]\_RTC", cpu => "10", mem => "5", cluster_out => "$output/progress/$pre\_$uID\_$gpair[0]\_RTC.log");
	    my $standardParams = Schedule::queuing(%stdParams);
	    `$standardParams->{submit} $standardParams->{job_name} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $JAVA/java -Xms256m -Xmx5g -XX:-UseGCOverheadLimit -Djava.io.tmpdir=/scratch/$uID -jar $GATK/GenomeAnalysisTK.jar -T RealignerTargetCreator -R $REF_SEQ $multipleTargets -S LENIENT --known $DB_SNP -nt 10 -rf BadCigar --out $output/intFiles/$pre\_$gpair[0]\_indelRealigner.intervals $bgroup`;
	    `/bin/touch $output/progress/$pre\_$uID\_$gpair[0]\_RTC.done`;
	    $rtc_jid = "$pre\_$uID\_$gpair[0]\_RTC";
	    $ran_rtc = 1;
	}
	
	if(!-e "$output/progress/$pre\_$uID\_$gpair[0]\_IR.done" || $ran_rtc){
	    sleep(2);
	    my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$gpair[0]\_IR", job_hold => "$rtc_jid", cpu => "1", mem => "15", cluster_out => "$output/progress/$pre\_$uID\_$gpair[0]\_IR.log");
	    my $standardParams = Schedule::queuing(%stdParams);
	    `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $JAVA/java -Xms256m -Xmx15g -XX:-UseGCOverheadLimit -Djava.io.tmpdir=/scratch/$uID -jar $GATK/GenomeAnalysisTK.jar -T IndelRealigner -R $REF_SEQ $multipleTargets -S LENIENT --knownAlleles $DB_SNP --targetIntervals $output/intFiles/$pre\_$gpair[0]\_indelRealigner.intervals --maxReadsForRealignment 500000 --maxReadsInMemory 3000000 --maxReadsForConsensuses 500000 -rf BadCigar --out $output/intFiles/$pre\_$gpair[0]\_indelRealigned.bam $bgroup`;
	    `/bin/touch $output/progress/$pre\_$uID\_$gpair[0]\_IR.done`;
	    push @ir_jids, "$pre\_$uID\_$gpair[0]\_IR";
	    $ran_ir = 1;
	}
	
	push @indelBams, "-I $output/intFiles/$pre\_$gpair[0]\_indelRealigned.bam";
    }
	
    my $irBams = join(" ", @indelBams);
    my $ran_br = 0;
    my $brj = '';
    my $irj = join(",", @ir_jids);
    if(!-e "$output/progress/$pre\_$uID\_$gpair[0]\_BR.done" || $ran_ir){
	sleep(2);
	my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$gpair[0]\_BR", job_hold => "$irj", cpu => "12", mem => "40", cluster_out => "$output/progress/$pre\_$uID\_$gpair[0]\_BR.log");
	my $standardParams = Schedule::queuing(%stdParams);
	`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $JAVA/java -Xms256m -Xmx30g -XX:-UseGCOverheadLimit -Djava.io.tmpdir=/scratch/$uID -jar $GATK/GenomeAnalysisTK.jar -T BaseRecalibrator -l INFO -R $REF_SEQ -S LENIENT --knownSites $DB_SNP --covariate ContextCovariate --covariate CycleCovariate --covariate QualityScoreCovariate --covariate ReadGroupCovariate -rf BadCigar --num_cpu_threads_per_data_thread 12 --out $output/intFiles/$pre\_$gpair[0]\_recal_data.grp $irBams`;
	`/bin/touch $output/progress/$pre\_$uID\_$gpair[0]\_BR.done`;
	$brj = "$pre\_$uID\_$gpair[0]\_BR";
	$ran_br = 1;
    }
        
    my $ran_pr = 0;
    my $prj = '';
    if(!-e "$output/progress/$pre\_$uID\_$gpair[0]\_PR.done" || $ran_br){
	sleep(2);
	my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$gpair[0]\_PR", job_hold => "$brj", cpu => "6", mem => "30", cluster_out => "$output/progress/$pre\_$uID\_$gpair[0]\_PR.log");
	my $standardParams = Schedule::queuing(%stdParams);
	`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $JAVA/java -Xms256m -Xmx30g -XX:-UseGCOverheadLimit -Djava.io.tmpdir=/scratch/$uID -jar $GATK/GenomeAnalysisTK.jar -T PrintReads -R $REF_SEQ $multipleTargets --emit_original_quals -BQSR $output/intFiles/$pre\_$gpair[0]\_recal_data.grp --num_cpu_threads_per_data_thread 6 -rf BadCigar --out $output/intFiles/$pre\_$gpair[0]\_indelRealigned_recal.bam $irBams`;
	`/bin/touch $output/progress/$pre\_$uID\_$gpair[0]\_PR.done`;
	$prj = "$pre\_$uID\_$gpair[0]\_PR";
	push @prg_jids, "$pre\_$uID\_$gpair[0]\_PR";
	$ran_pr = 1;
	$ran_pr_glob = 1;
    }
    
    push @processedBams, "-I $output/intFiles/$pre\_$gpair[0]\_indelRealigned_recal.bam";
        
    if(!-e "$output/progress/$pre\_$uID\_$gpair[0]\_SSF.done" || $ran_pr){
	sleep(2);
	my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$gpair[0]\_SSF", job_hold => "$prj", cpu => "1", mem => "10", cluster_out => "$output/progress/$pre\_$uID\_$gpair[0]\_SSF.log");
	my $standardParams = Schedule::queuing(%stdParams);
	`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $JAVA/java -Xms256m -Xmx10g -XX:-UseGCOverheadLimit -Djava.io.tmpdir=/scratch/$uID -jar $GATK/GenomeAnalysisTK.jar -T SplitSamFile -R $REF_SEQ -I $output/intFiles/$pre\_$gpair[0]\_indelRealigned_recal.bam --outputRoot $output/alignments/$pre\_indelRealigned_recal_`;
	`/bin/touch $output/progress/$pre\_$uID\_$gpair[0]\_SSF.done`;
	push @ssf_jids, "$pre\_$uID\_$gpair[0]\_SSF";
	$ran_ssf = 1;
    }
}

my $ssfj = join(",", @ssf_jids);
push @all_jids, @ssf_jids;
my @mq_metrics_jid = ();
my $ran_mqm = 0;
if(!-e "$output/progress/$pre\_$uID\_MQ.done" || $ran_ssf){
    sleep(2);
    foreach my $finalBam (@finalBams){
        my @sn = split(/\//, $finalBam);
        my $samp = $sn[-1];
        $samp =~ s/\.bam//g;
        $samp =~ s/$pre\_indelRealigned_recal_//g;
 
	if(!-e "$output/progress/$pre\_$uID\_MQ_METRICS_$samp\.done" || $ran_ssf){
	    my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_MQ_METRICS_$samp", job_hold => "$ssfj", cpu => "1", mem => "10", cluster_out => "$output/progress/$pre\_$uID\_MQ_METRICS_$samp\.log");
	    my $standardParams = Schedule::queuing(%stdParams);
	    `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $JAVA/java -Djava.io.tmpdir=/scratch/$uID -jar $PICARD/picard.jar MeanQualityByCycle INPUT=$finalBam OUTPUT=$output/intFiles/$pre\_MeanQualityByCycle_$samp.txt CHART_OUTPUT=$output/intFiles/$pre\_MeanQualityByCycle_$samp.pdf REFERENCE_SEQUENCE=$REF_SEQ VALIDATION_STRINGENCY=LENIENT ASSUME_SORTED=true TMP_DIR=/scratch/$uID`;
	    push @mq_metrics_jid, "$pre\_$uID\_MQ_METRICS_$samp";
	    `/bin/touch $output/progress/$pre\_$uID\_MQ_METRICS_$samp\.done`;
	    $ran_mqm = 1; 
	}
    }
}

my $mqmj = join(",", @mq_metrics_jid);
my $ran_mmqm = 0;
if(!-e "$output/progress/$pre\_$uID\_MQ.done" || $ran_mqm){
    my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_MERGE_MQ", job_hold => "$mqmj", cpu => "1", mem => "1", cluster_out => "$output/progress/$pre\_$uID\_MERGE_MQ.log");
    my $standardParams = Schedule::queuing(%stdParams);
    `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $PYTHON/python $Bin/qc/mergeMeanQualityHistograms.py $output '*_MeanQualityByCycle_*.txt' $output/metrics/$pre\_post_recal_MeanQualityByCycle.txt $output/metrics/$pre\_pre_recal_MeanQualityByCycle.txt`;
    `/bin/touch $output/progress/$pre\_$uID\_MERGE_MQ.done`;
    push @all_jids, "$pre\_$uID\_MERGE_MQ";
    $ran_mmqm = 1;
}

my $allj = join(",", @all_jids);
if(!-e "$output/progress/$pre\_$uID\_RSYNC_1.done" || $ran_ssf || $ran_mmqm){
    sleep(2);
    my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_RSYNC_1", job_hold => "$allj", cpu => "1", mem => "1", cluster_out => "$output/progress/$pre\_$uID\_RSYNC_1.log");
    my $standardParams = Schedule::queuing(%stdParams);
    `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams /usr/bin/rsync -azvP --exclude 'intFiles' --exclude 'progress' --exclude 'variants' --exclude 'metrics' $curDir $rsync`;
    push @all_jids, "$pre\_$uID\_RSYNC_1";
    `/bin/touch $output/progress/$pre\_$uID\_RSYNC_1.done`;
}

if($nosnps){
    exit;
}

`/bin/mkdir -m 775 -p $output/variants`;
`/bin/mkdir -m 775 -p $output/variants/snpsIndels`;
`/bin/mkdir -m 775 -p $output/variants/snpsIndels/haplotypecaller`;
my $ran_hc = 0;
my $ran_ug_snp = 0;
my $ran_ug_indel = 0;
my $hcj = '';
my $ugsj = '';
my $ugij = '';
my $prgj = join(",", @prg_jids);

my $irBams2 = join(" ", @processedBams);    
if($ug){
    if(!-e "$output/progress/$pre\_$uID\_UG_SNP.done" || $ran_pr_glob){
	sleep(2);
	my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_UG_SNP", job_hold => "$prgj", cpu => "12", mem => "48", cluster_out => "$output/progress/$pre\_$uID\_UG_SNP.log");
	my $standardParams = Schedule::queuing(%stdParams);
	`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $JAVA/java -Xms256m -Xmx24g -XX:-UseGCOverheadLimit -Djava.io.tmpdir=/scratch/$uID -jar $GATK/GenomeAnalysisTK.jar -T UnifiedGenotyper -R $REF_SEQ --reference_sample_name $species $multipleTargets --dbsnp $DB_SNP --downsampling_type NONE --annotateNDA --annotation AlleleBalance --annotation AlleleBalanceBySample --annotation HardyWeinberg --genotype_likelihoods_model SNP --read_filter BadCigar --num_cpu_threads_per_data_thread 12 --out $output/intFiles/$pre\_UnifiedGenotyper_SNP.vcf $irBams2`;
	`/bin/touch $output/progress/$pre\_$uID\_UG_SNP.done`;
	$ugsj = "$pre\_$uID\_UG_SNP";
	$ran_ug_snp = 1;
    }
    
    if(!-e "$output/progress/$pre\_$uID\_UG_INDEL.done" || $ran_pr_glob){
	sleep(2);
	my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_UG_INDEL", job_hold => "$prgj", cpu => "12", mem => "48", cluster_out => "$output/progress/$pre\_$uID\_UG_INDEL.log");
	my $standardParams = Schedule::queuing(%stdParams);
	`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $JAVA/java -Xms256m -Xmx24g -XX:-UseGCOverheadLimit -Djava.io.tmpdir=/scratch/$uID -jar $GATK/GenomeAnalysisTK.jar -T UnifiedGenotyper -R $REF_SEQ --reference_sample_name $species $multipleTargets --downsampling_type NONE --annotateNDA --annotation AlleleBalance --annotation AlleleBalanceBySample --annotation HardyWeinberg --genotype_likelihoods_model INDEL --read_filter BadCigar --num_cpu_threads_per_data_thread 12 --out $output/intFiles/$pre\_UnifiedGenotyper_INDEL.vcf $irBams2`;
	`/bin/touch $output/progress/$pre\_$uID\_UG_INDEL.done`;
	$ugij = "$pre\_$uID\_UG_INDEL";
	$ran_ug_indel = 1;
    }    
}

if(!-e "$output/progress/$pre\_$uID\_HC.done" || $ran_pr_glob){
    sleep(2);
    my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_HC", job_hold => "$prgj", cpu => "24", mem => "90", cluster_out => "$output/progress/$pre\_$uID\_HC.log");
    my $standardParams = Schedule::queuing(%stdParams);
    `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $JAVA/java -Xms256m -Xmx90g -XX:-UseGCOverheadLimit -Djava.io.tmpdir=/scratch/$uID -jar $GATK/GenomeAnalysisTK.jar -T HaplotypeCaller -R $REF_SEQ $multipleTargets --dbsnp $DB_SNP --downsampling_type NONE --annotation AlleleBalanceBySample --annotation ClippingRankSumTest --read_filter BadCigar --num_cpu_threads_per_data_thread 24 --out $output/variants/snpsIndels/haplotypecaller/$pre\_HaplotypeCaller.vcf $irBams2`;
    `/bin/touch $output/progress/$pre\_$uID\_HC.done`;
    $hcj = "$pre\_$uID\_HC";
    $ran_hc = 1;
}

sleep(2);
# Run this anyway, it will go through the function and make sure everything was ran
&generateMaf("$output/variants/snpsIndels/haplotypecaller/$pre\_HaplotypeCaller.vcf", 'haplotypecaller', "$hcj,$ssfj", $ran_hc);

if($ug){
    `/bin/mkdir -m 775 -p $output/variants/snpsIndels/unifiedgenotyper`;
    if(!-e "$output/progress/$pre\_$uID\_CV_UG_RAW.done" || $ran_ug_snp || $ran_ug_indel){
	sleep(2);
	my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_UG_RAW", job_hold => "$ugsj,$ugij", cpu => "1", mem => "2", cluster_out => "$output/progress/$pre\_$uID\_CV_UG_RAW.log");
	my $standardParams = Schedule::queuing(%stdParams);
	`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $JAVA/java -Xms256m -Xmx2g -XX:-UseGCOverheadLimit -Djava.io.tmpdir=/scratch/$uID -jar $GATK/GenomeAnalysisTK.jar -T CombineVariants -R $REF_SEQ -o $output/intFiles/$pre\_UnifiedGenotyper_RAW.vcf --assumeIdenticalSamples --variant $output/intFiles/$pre\_UnifiedGenotyper_SNP.vcf --variant $output/intFiles/$pre\_UnifiedGenotyper_INDEL.vcf`;
	`/bin/touch $output/progress/$pre\_$uID\_UG_RAW.done`;
    }

    my $ran_vf_ug_snp = 0;
    my @vfug_jids = ();
    if(!-e "$output/progress/$pre\_$uID\_VF_UG_SNP.done" || $ran_ug_snp){
	sleep(2);
	my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_VF_UG_SNP", job_hold => "$ugsj", cpu => "1", mem => "2", cluster_out => "$output/progress/$pre\_$uID\_VF_UG_SNP.log");
	my $standardParams = Schedule::queuing(%stdParams);
	`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $JAVA/java -Xms256m -Xmx2g -XX:-UseGCOverheadLimit -Djava.io.tmpdir=/scratch/$uID -jar $GATK/GenomeAnalysisTK.jar -T VariantFiltration -R $REF_SEQ --mask $output/intFiles/$pre\_UnifiedGenotyper_INDEL.vcf --maskName nearIndel --variant $output/intFiles/$pre\_UnifiedGenotyper_SNP.vcf -o $output/intFiles/$pre\_UnifiedGenotyper_SNP_vf.vcf --clusterWindowSize 10 --filterExpression \\"QD \\< 2.0\\" --filterExpression \\"MQ \\< 40.0\\" --filterExpression \\"FS \\> 60.0\\" --filterExpression \\"HaplotypeScore \\> 13.0\\" --filterExpression \\"MQRankSum \\< -12.5\\" --filterExpression \\"ReadPosRankSum \\< -8.0\\" --filterName QDFilter --filterName MQFilter --filterName FSFilter --filterName HSFilter --filterName MQRSFilter --filterName ReadPosFilter`;
	`/bin/touch $output/progress/$pre\_$uID\_VF_UG_SNP.done`;
	push @vfug_jids, "$pre\_$uID\_VF_UG_SNP";
	$ran_vf_ug_snp = 1;
    }

    my $ran_vf_ug_indel = 0;
    if(!-e "$output/progress/$pre\_$uID\_VF_UG_INDEL.done" || $ran_ug_indel){
	sleep(2);
	my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_VF_UG_INDEL", job_hold => "$ugij", cpu => "1", mem => "2", cluster_out => "$output/progress/$pre\_$uID\_VF_UG_INDEL.log");
	my $standardParams = Schedule::queuing(%stdParams);
	`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $JAVA/java -Xms256m -Xmx2g -XX:-UseGCOverheadLimit -Djava.io.tmpdir=/scratch/$uID -jar $GATK/GenomeAnalysisTK.jar -T VariantFiltration -R $REF_SEQ --variant $output/intFiles/$pre\_UnifiedGenotyper_INDEL.vcf -o $output/intFiles/$pre\_UnifiedGenotyper_INDEL_vf.vcf --clusterWindowSize 10 --filterExpression \\"QD \\< 2.0\\" --filterExpression \\"ReadPosRankSum \\< -20.0\\" --filterExpression \\"InbreedingCoeff \\< -0.8\\" --filterExpression \\"FS \\> 200.0\\" --filterName QDFilter --filterName ReadPosFilter --filterName InbreedingFilter --filterName FSFilter`;
	`/bin/touch $output/progress/$pre\_$uID\_VF_UG_INDEL.done`;
	push @vfug_jids, "$pre\_$uID\_VF_UG_INDEL";
	$ran_vf_ug_indel = 1;
    }

    my $ran_cv_ug_si = 0;
    my $cvugsij = '';
    if(!-e "$output/progress/$pre\_$uID\_CV_UG_SI.done" || $ran_ug_snp || $ran_ug_indel){
	sleep(2);
	my $vfugj = join(",", @vfug_jids);
	my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_CV_UG_SI", job_hold => "$vfugj", cpu => "1", mem => "2", cluster_out => "$output/progress/$pre\_$uID\_CV_UG_SI.log");
	my $standardParams = Schedule::queuing(%stdParams);
	`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $JAVA/java -Xms256m -Xmx2g -XX:-UseGCOverheadLimit -Djava.io.tmpdir=/scratch/$uID -jar $GATK/GenomeAnalysisTK.jar -T CombineVariants -R $REF_SEQ -o $output/variants/snpsIndels/unifiedgenotyper/$pre\_UnifiedGenotyper.vcf --assumeIdenticalSamples --variant $output/progress/$pre\_UnifiedGenotyper_SNP_vf.vcf --variant $output/progress/$pre\_UnifiedGenotyper_INDEL_vf.vcf`;
	`/bin/touch $output/progress/$pre\_$uID\_CV_UG_SI.done`;
        $cvugsij = "$pre\_$uID\_CV_UG_SI";
	$ran_cv_ug_si = 1;
    }
        
    if(!-e "$output/progress/$pre\_$uID\_MAF_UG.done" || $ran_cv_ug_si){  
	sleep(2);
	&generateMaf("$pre\_UnifiedGenotyper.vcf", 'unifiedgenotyper', "$cvugsij", $ran_cv_ug_si);
 	`/bin/touch $output/progress/$pre\_$uID\_MAF_UG.done`;
    }
}

my $hasPair = 0;

if($pair){
    `/bin/mkdir -m 775 -p $output/variants/snpsIndels/haplotect`;
    #`/bin/mkdir -m 775 -p $output/variants/copyNumber`;
    #`/bin/mkdir -m 775 -p $output/variants/copyNumber/facets`;

    open(PAIR, "$pair") or die "Can't open $pair file";
    my %submitted_lns = ();
    my @mu_jids = ();
    my $ran_mutect_glob = 0;
    my $haplotect_run = 0;
    my $facets_run = 0;
    my @facets_jid = ();

       while(<PAIR>){
	chomp;
	
	my @data = split(/\s+/, $_);

	if($data[0] =~ /^NA$/i || $data[1] =~ /^NA$/i){
	    next;
	}
        ## This means there really is a sample pair, haplotect should run.
        $hasPair=1;

	`/bin/mkdir -m 775 -p $output/variants/snpsIndels/mutect`;
	my $ran_mutect = 0;
	my $mutectj = '';
	if(!-e "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_MUTECT.done" || $ran_ssf){  
	    sleep(2);
	    my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$data[0]\_$data[1]\_MUTECT", job_hold => "$ssfj", cpu => "2", mem => "4", cluster_out => "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_MUTECT.log");
	    my $standardParams = Schedule::queuing(%stdParams);
	    `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $JAVA/java -Xmx4g -Djava.io.tmpdir=/scratch/$uID -jar $MUTECT/muTect.jar --analysis_type MuTect --reference_sequence $REF_SEQ --dbsnp $DB_SNP --input_file:normal $output/alignments/$pre\_indelRealigned_recal\_$data[0]\.bam --input_file:tumor $output/alignments/$pre\_indelRealigned_recal\_$data[1]\.bam --vcf $output/variants/snpsIndels/mutect/$pre\_$data[0]\_$data[1]\_mutect_calls.vcf --out $output/variants/snpsIndels/mutect/$pre\_$data[0]\_$data[1]\_mutect_calls.txt -rf BadCigar --enable_extended_output --downsampling_type NONE`;
	    `/bin/touch $output/progress/$pre\_$uID\_$data[0]\_$data[1]\_MUTECT.done`;
	    $mutectj = "$pre\_$uID\_$data[0]\_$data[1]\_MUTECT";
	    push @mu_jids, "$pre\_$uID\_$data[0]\_$data[1]\_MUTECT";
	    push @all_jids, $mutectj;
	    $ran_mutect = 1;
	    $ran_mutect_glob = 1;
	}

	###if(!-e "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_MUTECT_MAF.done" || $ran_mutect){
	### sleep(2);
	###&generateMaf("$output/variants/snpsIndels/mutect/$pre\_$data[0]\_$data[1]\_mutect_calls.vcf", 'mutect', "$pre\_$uID\_$data[0]\_$data[1]\_MUTECT", $data[0], $data[1]);
	###`/bin/touch $output/progress/$pre\_$uID\_$data[0]\_$data[1]\_MUTECT_MAF.done`;
	###}

	if($somaticsniper){
	    `/bin/mkdir -m 775 -p $output/variants/snpsIndels/somaticsniper`;
	    my $ran_somatic_sniper = 0;
	    my $ssj = '';
	    if(!-e "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_SOMATIC_SNIPER.done" || $ran_ssf){  
		sleep(2);
		my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$data[0]\_$data[1]\_SOMATIC_SNIPER", job_hold => "$ssfj", cpu => "2", mem => "4", cluster_out => "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_SOMATIC_SNIPER.log");
		my $standardParams = Schedule::queuing(%stdParams);
		`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $SOMATIC_SNIPER/bam-somaticsniper -F vcf -f $REF_SEQ -q 1 $output/alignments/$pre\_indelRealigned_recal\_$data[1]\.bam $output/alignments/$pre\_indelRealigned_recal\_$data[0]\.bam $output/variants/snpsIndels/somaticsniper/$pre\_indelRealigned_recal\_$data[0]\_$data[1]\_somatic_sniper.vcf`;
		`/bin/touch $output/progress/$pre\_$uID\_$data[0]\_$data[1]\_SOMATIC_SNIPER.done`;
		$ssj = "$pre\_$uID\_$data[0]\_$data[1]\_SOMATIC_SNIPER";
		push @all_jids, $ssj;
		$ran_somatic_sniper = 1;
	    }

	    ###if(!-e "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_SOMATIC_SNIPER_MAF.done" || $ran_somatic_sniper){
	    ### `/common/sge/bin/lx24-amd64/qsub -N $pre\_$uID\_$data[0]\_$data[1]\_SOMATIC_SNIPER_MAF -hold_jid $pre\_$uID\_$data[0]\_$data[1]\_SOMATIC_SNIPER -pe alloc 1 -l virtual_free=2G -q lau.q,lcg.q,nce.q $Bin/qCMD $Bin/maf/vcf2maf0.py -i $output/variants/snpsIndels/somaticsniper/$pre\_indelRealigned_recal\_$data[0]\_$data[1]\_somatic_sniper.vcf -c somaticsniper -o $output/variants/snpsIndels/somaticsniper/$pre\_indelRealigned_recal\_$data[0]\_$data[1]\_somatic_sniper_MAF.txt -n $data[0] -t $data[1]`;
	    ###`/bin/touch $output/progress/$pre\_$uID\_$data[0]\_$data[1]\_SOMATIC_SNIPER_MAF.done`;
	    ###}
	}

	if($virmid){
	    my $ran_virmid = 0;
	    if(!-e "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_VIRMID.done" || $ran_ssf){  
		sleep(2);
		if(-d "$output/variants/snpsIndels/virmid/$data[0]\_$data[1]\_virmid"){
		    `/bin/rm -rf $output/variants/snpsIndels/virmid/$data[0]\_$data[1]\_virmid`;
		}
		`/bin/mkdir -m 775 -p $output/variants/snpsIndels/virmid/$data[0]\_$data[1]\_virmid`;
		my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$data[0]\_$data[1]\_VIRMID", job_hold => "$ssfj", cpu => "4", mem => "12", cluster_out => "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_VIRMID.log");
		my $standardParams = Schedule::queuing(%stdParams);
		`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $JAVA/java -Xms256m -Xmx12g -XX:-UseGCOverheadLimit -Djava.io.tmpdir=/scratch/$uID -jar $VIRMID/Virmid.jar -R $REF_SEQ -D $output/alignments/$pre\_indelRealigned_recal\_$data[1]\.bam -N $output/alignments/$pre\_indelRealigned_recal\_$data[0]\.bam -t 4 -o $pre\_$data[0]\_$data[1]\_virmid -w $output/variants/snpsIndels/virmid/$data[0]\_$data[1]\_virmid`;
		`/bin/touch $output/progress/$pre\_$uID\_$data[0]\_$data[1]\_VIRMID.done`;
		push @all_jids, "$pre\_$uID\_$data[0]\_$data[1]\_VIRMID";
		$ran_virmid = 1;
	    }
	}
	
	if($strelka){
	    my $ran_strelka_config = 0;
	    if(!-e "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_CONFIG.done" || $ran_ssf){  
		if(-d "$output/variants/snpsIndels/strelka/$data[0]\_$data[1]\_strelka"){
		    ### STRELKA DIES IF DIR ALREADY EXISTS
		    `/bin/rm -rf $output/variants/snpsIndels/strelka//$data[0]\_$data[1]\_strelka`;
		}
		
		my @lns_jids = ();
		### NOTE: Strelka only recognizes X.bam.bai as the index for X.bam, not X.bai
		if((!-e "$output/progress/$pre\_indelRealigned_recal\_$data[0]\_LNS.done" || $ran_ssf)  && !-e "$output/alignments/$pre\_indelRealigned_recal\_$data[0]\.bam.bai" && !$submitted_lns{$data[0]}){
		    sleep(2);
		    my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_indelRealigned_recal\_$data[0]\_LNS", job_hold => "$ssfj", cpu => "1", mem => "1", cluster_out => "$output/progress/$pre\_indelRealigned_recal\_$data[0]\_LNS.log");
		    my $standardParams = Schedule::queuing(%stdParams);
		    `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams /bin/ln -s $pre\_indelRealigned_recal\_$data[0]\.bai $output/alignments/$pre\_indelRealigned_recal\_$data[0]\.bam.bai`;
		    #push @lns_jids, "$pre\_indelRealigned_recal\_$data[0]\_LNS";
		    $submitted_lns{$data[0]} = 1;
		    `/bin/touch $output/progress/$pre\_indelRealigned_recal\_$data[0]\_LNS.done`;
		}
		
		if((!-e "$output/progress/$pre\_indelRealigned_recal\_$data[1]\_LNS.done" || $ran_ssf) && !-e "$output/alignments/$pre\_indelRealigned_recal\_$data[1]\.bam.bai" && !$submitted_lns{$data[1]}){
		    sleep(2);
		    my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_indelRealigned_recal\_$data[1]\_LNS", job_hold => "$ssfj", cpu => "1", mem => "1", cluster_out => "$output/progress/$pre\_indelRealigned_recal\_$data[1]\_LNS.log");
		    my $standardParams = Schedule::queuing(%stdParams);
		    `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams /bin/ln -s $pre\_indelRealigned_recal\_$data[1]\.bai $output/alignments/$pre\_indelRealigned_recal\_$data[1]\.bam.bai`;
		    #push @lns_jids, "$pre\_indelRealigned_recal\_$data[1]\_LNS";
		    $submitted_lns{$data[1]} = 1;
		    `/bin/touch $output/progress/$pre\_indelRealigned_recal\_$data[1]\_LNS.done`;
		}
		
		if($submitted_lns{$data[0]}){
		    push @lns_jids, "$pre\_$uID\_indelRealigned_recal\_$data[0]\_LNS";
		}
		if($submitted_lns{$data[1]}){
		    push @lns_jids, "$pre\_$uID\_indelRealigned_recal\_$data[1]\_LNS";
		}
		my $lnsj = join(",", @lns_jids, $ssfj);
		sleep(2);
		### NOTE: strelka ONLY HAS CONFIG FOR BWA ALN, NOT SURE HOW IT WILL WORK WITH BWA MEM
		my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_CONFIG", job_hold => "$lnsj", cpu => "1", mem => "2", cluster_out => "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_CONFIG.log");
		my $standardParams = Schedule::queuing(%stdParams);	    
		`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $STRELKA/bin/configureStrelkaWorkflow.pl --normal=$output/alignments//$pre\_indelRealigned_recal\_$data[0]\.bam --tumor=$output/alignments//$pre\_indelRealigned_recal\_$data[1]\.bam --ref=$REF_SEQ --config=$STRELKA/etc/strelka_config_bwa_default.ini --output-dir=$output/variants/snpsIndels/strelka//$data[0]\_$data[1]\_strelka`;
		`/bin/touch $output/progress/$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_CONFIG.done`;
		$ran_strelka_config = 1;
	    }

	    my $ran_strelka_run = 0;
	    if(!-e "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_RUN.done" || $ran_strelka_config){
		sleep(2);
		my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_RUN", job_hold => "$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_CONFIG", cpu => "8", mem => "16", cluster_out => "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_RUN.log");
		my $standardParams = Schedule::queuing(%stdParams);
		`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams /usr/bin/make -C $output/variants/snpsIndels/strelka/$data[0]\_$data[1]\_strelka -j 8`;
		`/bin/touch $output/progress/$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_RUN.done`;
		$ran_strelka_run = 1;
	    }

	    if($ran_strelka_run){
		sleep(2);
		my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_CLEANUP", job_hold => "$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_RUN", cpu => "1", mem => "1", cluster_out => "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_CLEANUP.log");
		my $standardParams = Schedule::queuing(%stdParams);
		`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams /bin/rm -rf $output/variants/snpsIndels/strelka/$data[0]\_$data[1]\_strelka/config $output/variants/snpsIndels/strelka/$data[0]\_$data[1]\_strelka/chromosomes $output/variants/snpsIndels/strelka/$data[0]\_$data[1]\_strelka/Makefile $output/variants/snpsIndels/strelka/$data[0]\_$data[1]\_strelka/task.complete`;
		push @all_jids, "$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_CLEANUP";
	    }
	    
	    ###if(!-e "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_RUN_MAF.done" || $ran_strelka_run){
	    ### my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_RUN_MAF", job_hold => "$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_RUN", cpu => "1", mem => "1", cluster_out => "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_RUN_MAF.log");
	    ###my $standardParams = Schedule::queuing(%stdParams);
	    ###`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $PYTHON/python $Bin/maf/vcf2maf0.py -i $output/variants/snpsIndels/strelka/$data[0]\_$data[1]\_strelka/results/all.somatic.snvs.vcf -c strelka -o $output/variants/snpsIndels/strelka/$data[0]\_$data[1]\_strelka/results/$pre\_$data[0]\_$data[1]\_STRELKA_all.somatic.snvs_MAF.txt -n $data[0] -t $data[1]`;
	    
	    ###`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $PYTHON/python $Bin/maf/vcf2maf0.py -i $output/variants/snpsIndels/strelka/$data[0]\_$data[1]\_strelka/results/passed.somatic.snvs.vcf -c strelka -o $output/variants/snpsIndels/strelka/$data[0]\_$data[1]\_strelka/results/$pre\_$data[0]\_$data[1]\_STRELKA_passed.somatic.snvs_MAF.txt -n $data[0] -t $data[1]`;
	    
	    ###`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $PYTHON/python $Bin/maf/vcf2maf0.py -i $output/variants/snpsIndels/strelka/$data[0]\_$data[1]\_strelka/results/all.somatic.indels.vcf -c strelka -o $output/variants/snpsIndels/strelka/$data[0]\_$data[1]\_strelka/results/$pre\_$data[0]\_$data[1]\_STRELKA_all.somatic.indels_MAF.txt -n $data[0] -t $data[1]`;
	    
	    ###`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $PYTHON/python $Bin/maf/vcf2maf0.py -i $output/variants/snpsIndels/strelka/$data[0]\_$data[1]\_strelka/results/passed.somatic.indels.vcf -c strelka -o $output/variants/snpsIndels/strelka/$data[0]\_$data[1]\_strelka/results/$pre\_$data[0]\_$data[1]\_STRELKA_passed.somatic.indels_MAF.txt -n $data[0] -t $data[1]`;
	    ###`/bin/touch $output/progress/$pre\_$uID\_$data[0]\_$data[1]\_STRELKA_RUN_MAF.done`;
	    ###	}
	}

	if($scalpel){
	    my $ran_scalpel = 0;
	    if(!-e "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_SCALPEL.done" || $ran_ssf){
		sleep(2);
		`/bin/mkdir -m 775 -p $output/variants/snpsIndels/scalpel/$data[0]\_$data[1]\_scalpel`;
		my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$data[0]\_$data[1]\_SCALPEL", job_hold => "$ssfj", cpu => "24", mem => "90", cluster_out => "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_SCALPEL.log");
		my $standardParams = Schedule::queuing(%stdParams);
		`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $SCALPEL/scalpel --somatic --normal $output/alignments/$pre\_indelRealigned_recal\_$data[0]\.bam --tumor $output/alignments/$pre\_indelRealigned_recal\_$data[1]\.bam --bed $targets_bed_padded --ref $REF_SEQ --dir $output/variants/snpsIndels/scalpel/$data[0]\_$data[1]\_scalpel --numprocs 24`;
		`/bin/touch $output/progress/$pre\_$uID\_$data[0]\_$data[1]\_SCALPEL.done`;
		$ran_scalpel = 1;
	    }
	    
	    if($ran_scalpel){
		sleep(2);
		my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$data[0]\_$data[1]\_SCALPEL_CLEANUP", job_hold => "$pre\_$uID\_$data[0]\_$data[1]\_SCALPEL", cpu => "1", mem => "1", cluster_out => "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_SCALPEL_CLEANUP.log");
		my $standardParams = Schedule::queuing(%stdParams);
		`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams /bin/rm -rf $output/variants/snpsIndels/scalpel/$data[0]\_$data[1]\_scalpel/main/ $output/variants/snpsIndels/scalpel/$data[0]\_$data[1]\_scalpel/validation/`;
		push @all_jids, "$pre\_$uID\_$data[0]\_$data[1]\_SCALPEL_CLEANUP";
	    }
	}

	if($varscan){
	    ###if(!-e "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_VARSCAN_SOMATIC_MAF.done" || $ran_varscan_somatic){
	    ###`/common/sge/bin/lx24-amd64/qsub -N $pre\_$uID\_$data[0]\_$data[1]\_VARSCAN_SOMATIC_MAF -hold_jid $pre\_$uID\_$data[0]\_$data[1]\_VARSCAN_SOMATIC -pe alloc 1 -l virtual_free=2G -q lau.q,lcg.q,nce.q $Bin/qCMD $Bin/maf/vcf2maf0.py -i $output/variants/varscan/$pre\_$data[0]\_$data[1]\_varscan_somatic\.snp.vcf -c varscan -o $output/variants/varscan/$pre\_$data[0]\_$data[1]\_varscan_somatic\.snp_MAF.txt -n $data[0] -t $data[1]`;
	}


=begin FOR_FACETS
        ## Here we will add the facets scripts
        ## These are the #'s Nick uses
        my $MINCOV=0;
        my $BASEQ=20;
        my $MAPQ=15;

        ## Set up tumor and normal counts
        `/bin/mkdir -m 775 -p $output/variants/copyNumber/facets/$data[0]\_$data[1]\_facets`;
        `/bin/mkdir -m 775 -p $output/variants/copyNumber/facets/$data[0]\_$data[1]\_facets/tmp`;
        my $facetsSETUP_jid = '';
        my $facets_setup = 0;
        if($hasPair && (! -e "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_facets_SETUP.done" || $ssfj )) {
            my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$data[0]\_facets_SETUP",  cpu => "4", mem => "5", job_hold => "$ssfj", cluster_out => "$output/progress/$pre\_$uID\_$data[0]\_facets_SETUP.log");
            my $standardParams = Schedule::queuing(%stdParams);
            my %addParams = (runtime => "30");
            my $additionalParams = Schedule::additionalParams(%addParams);
            `$standardParams->{submit} $standardParams->{job_name} $standardParams->{cpu} $standardParams->{mem} $standardParams->{job_hold} $standardParams->{cluster_out} $additionalParams $Bin/facets/bin/GetBaseCounts --filter_improper_pair --sort_output --fasta $REF_SEQ --vcf $DB_SNP --maq $MAPQ --baq $BASEQ --cov $MINCOV --bam $output/alignments/$pre\_indelRealigned_recal\_$data[0]\.bam --out $output/variants/copyNumber/facets/$data[0]\_$data[1]\_facets/tmp/$pre\_indelRealigned_recal\_$data[0].dat`;

            %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$data[1]\_facets_SETUP",  cpu => "4", mem => "5", job_hold => "$ssfj", cluster_out => "$output/progress/$pre\_$uID\_$data[1]\_facets_SETUP.log");
            my $standardParams2 = Schedule::queuing(%stdParams);
            %addParams = (runtime => "30");
            my $additionalParams2 = Schedule::additionalParams(%addParams);
            `$standardParams2->{submit} $standardParams2->{job_name} $standardParams2->{cpu} $standardParams2->{mem} $standardParams2->{job_hold} $standardParams2->{cluster_out} $additionalParams2 $Bin/facets/bin/GetBaseCounts --filter_improper_pair --sort_output --fasta $REF_SEQ --vcf $DB_SNP --maq $MAPQ --baq $BASEQ --cov $MINCOV --bam $output/alignments/$pre\_indelRealigned_recal\_$data[1]\.bam --out $output/variants/copyNumber/facets/$data[0]\_$data[1]\_facets/tmp/$pre\_indelRealigned_recal\_$data[1].dat`;


            %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$data[0]\_$data[1]\_merge_counts_facets_SETUP",  cpu => "4", mem => "18", job_hold => "$pre\_$uID\_$data[0]\_facets_SETUP,$pre\_$uID\_$data[1]\_facets_SETUP", cluster_out => "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_facets_SETUP.log");
            my $standardParams3 = Schedule::queuing(%stdParams);
            %addParams = (runtime => "30");
            my $additionalParams3 = Schedule::additionalParams(%addParams);
            `$standardParams3->{submit} $standardParams3->{job_name} $standardParams3->{cpu} $standardParams3->{mem} $standardParams3->{job_hold} $standardParams3->{cluster_out} $additionalParams3 $Bin/facets/mergeTN.R  $output/variants/copyNumber/facets/$data[0]\_$data[1]\_facets/tmp/$pre\_indelRealigned_recal\_$data[1].dat  $output/variants/copyNumber/facets/$data[0]\_$data[1]\_facets/tmp/$pre\_indelRealigned_recal\_$data[0].dat $output/variants/copyNumber/facets/$data[0]\_$data[1]\_facets/tmp/$pre\_countsMerged_$data[0]\_$data[1].dat.gz`;

            $facets_setup = 1;
            `/bin/touch $output/progress/$pre\_$uID\_$data[0]\_$data[1]\_facets_SETUP.done`;
            $facetsSETUP_jid = "$pre\_$uID\_$data[0]\_$data[1]\_merge_counts_facets_SETUP";
        }
        ## now facets
        if($hasPair && (! -e "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_facets_RUN.done" || $facets_setup)){

            my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$data[0]\_$data[1]\_facets_RUN",  cpu => "3", mem => "2", job_hold => "$facetsSETUP_jid", cluster_out => "$output/progress/$pre\_$uID\_$data[0]\_$data[1]\_facets_RUN.log");
            my $standardParams = Schedule::queuing(%stdParams);
            my %addParams = (runtime => "10");
            my $additionalParams = Schedule::additionalParams(%addParams);
            `$standardParams->{submit} $standardParams->{job_name} $standardParams->{cpu} $standardParams->{mem} $standardParams->{job_hold} $standardParams->{cluster_out} $additionalParams $Bin/facets/facets_RUN.sh $FACETS_SUITE $FACETS_LIB $output/variants/copyNumber/facets/$data[0]\_$data[1]\_facets $data[0]\_$data[1] $output/variants/copyNumber/facets/$data[0]\_$data[1]\_facets/tmp/$pre\_countsMerged_$data[0]\_$data[1].dat $species 300 100`;
            push @facets_jid, "$pre\_$uID\_$data[0]\_$data[1]\_facets_RUN" ;
            $facets_run = 1;
            `/bin/touch $output/progress/$pre\_$uID\_$data[0]\_$data[1]\_facets_RUN.done`;
        }
        `/bin/echo "$data[1]\t$output/variants/copyNumber/facets/$data[0]\_$data[1]\_facets/$data[0]\_$data[1]\_hisens.Rdata" >> $output/variants/copyNumber/facets/facets_mapping.txt`;
=end FOR_FACETS
=cut
    
    }
    close PAIR;
    my $facets_haplotect_jid = '';
=begin FOR_FACETS
    if($hasPair && (! -e "$output/progress/$pre\_$uID\_merge_facets_seg.done" || $facets_run)){
        my $seg_outfile = "$output/variants/copyNumber/facets/$pre\_facets_merge_hisens.seg";
        if( -f "$seg_outfile"){
            unlink("$seg_outfile") or die "Cannot delete? $!";
        }
        my $facets_js = join(",", @facets_jid);

        my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_merge_facets_seg",  cpu => "1", mem => "1", job_hold => "$facets_js", cluster_out => "$output/progress/$pre\_$uID\_merge_facets_seg.log");
        my $standardParams = Schedule::queuing(%stdParams);
        my %addParams = (scheduler => "$scheduler", runtime => "1", priority_project=> "$priority_project", priority_group=> "$priority_group", queues => "lau.q,lcg.q,nce.q", rerun => "1", iounits => "0");
        my $additionalParams = Schedule::additionalParams(%addParams);
        `$standardParams->{submit} $standardParams->{job_name} $standardParams->{cpu} $standardParams->{mem} $standardParams->{job_hold} $standardParams->{cluster_out} $additionalParams $PERL/perl $Bin/facets/merge_facets_seg.pl -facets_dir $output/variants/copyNumber/facets -outfile $seg_outfile`;

        `/bin/touch $output/progress/$pre\_$uID\_merge_facets_seg.done`;
        $facets_haplotect_jid = "$pre\_$uID\_merge_facets_seg";
    }
=end FOR_FACETS
=cut

    if($hasPair && (!-e "$output/progress/$pre\_$uID\_HAPLOTECT.done" || $ran_mutect_glob || $ran_hc)){
        sleep(2);
        my $patientFile = "";
        if($patient){
            $patientFile = "-patient $patient";
        }
        my $muj = join(",", @mu_jids);
        my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_HAPLOTECT", job_hold => "$hcj,$muj", cpu => "4", mem => "8", cluster_out => "$output/progress/$pre\_$uID\_HAPLOTECT.log");
        my $standardParams = Schedule::queuing(%stdParams);
        `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $PERL/perl $Bin/haploTect_merge.pl -pair $pair -hc_vcf $output/variants/snpsIndels/haplotypecaller/$pre\_HaplotypeCaller.vcf -species $species -pre $pre -output $output/variants/snpsIndels/haplotect -mutect_dir $output/variants/snpsIndels/mutect -config $config $patientFile -align_dir $output/alignments/ -delete_temp`;

        $haplotect_run = 1;
        `/bin/touch $output/progress/$pre\_$uID\_HAPLOTECT.done`;
        $facets_haplotect_jid .= ",$pre\_$uID\_HAPLOTECT";
         push @all_jids, "$pre\_$uID\_HAPLOTECT";
    }

=begin FOR_FACETS

    if($hasPair && (!-e "$output/progress/$pre\_$uID\_join_maf.done" || $haplotect_run || $facets_run)){
        sleep(2);

        my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_join_maf", job_hold => "$facets_haplotect_jid", cpu => "4", mem => "8", cluster_out => "$output/progress/$pre\_$uID\_join_maf.log");
        my $standardParams = Schedule::queuing(%stdParams);
        `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $FACETS_SUITE/facets mafAnno -m $output/variants/snpsIndels/haplotect/$pre\_haplotect_VEP_MAF.txt -f $output/variants/copyNumber/facets/facets_mapping.txt -o $output/variants/$pre\_CMO_MAF.txt`;
        `/bin/touch $output/progress/$pre\_$uID\_join_maf.done`;
        push @all_jids, "$pre\_$uID\_join_maf";
    }

=end FOR_FACETS
=cut

}


my $allj2 = join(",", @all_jids);
my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_RSYNC_2", job_hold => "$allj2", cpu => "1", mem => "1", cluster_out => "$output/progress/$pre\_$uID\_RSYNC_2.log");
my $standardParams = Schedule::queuing(%stdParams);
`$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams /usr/bin/rsync -azvP --exclude 'intFiles' --exclude 'progress' $curDir $rsync`;
`/bin/touch $output/progress/$pre\_$uID\_RSYNC_2.done`;


sub generateMaf{
    my ($vcf, $type, $hold, $ran_hc, $normal_sample, $tumor_sample) = @_;

    my $n_sample = '';
    my $t_sample = '';
    if($normal_sample && $tumor_sample){
        $n_sample = "-normal_sample $normal_sample";
        $t_sample = "-tumor_sample $tumor_sample";
    }

    my $vcf_dir = dirname($vcf);
    my $jna = basename($vcf);
    $jna =~ s/\//_/g;

    my $patientFile = "";
    if($patient){
        $patientFile = "-patient $patient";
    }

    my $bgz_jid = '';
    my $bgzipped = 0;

    my @vcf_files;
    my @chr_maf_jids;
    # split and send each split thing to generate maf separately
    foreach my $c (1..19, 'X', 'Y', "$CHR_M"){
        if( !-e "$output/progress/$pre\_$uID\_$jna\_CHR$c\_MAF_UNPAIRED.done" || $ran_hc ){

            if((! -e "$vcf.gz" || $ran_hc) && !$bgzipped){
                $bgzipped = 1;
                my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$jna\_bgzip", job_hold => "$hold", cpu => "1", mem => "5", cluster_out => "$output/progress/$pre\_$uID\_$jna\_bgzip.log");
                my $standardParams = Schedule::queuing(%stdParams);
                `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams "$TABIX/bgzip -cf $vcf > $vcf.gz"`;

                 %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$jna\_bgzip_index", job_hold => "$pre\_$uID\_$jna\_bgzip", cpu => "1", mem => "5", cluster_out => "$output/progress/$pre\_$uID\_$jna\_bgzip_index.log");
                 $standardParams = Schedule::queuing(%stdParams);
                 `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $BCFTOOLS/bcftools index $vcf.gz`;

                 $bgz_jid = "$pre\_$uID\_$jna\_bgzip,$pre\_$uID\_$jna\_bgzip_index";
            }
            `/bin/mkdir -m 775 -p $vcf_dir/chrom_$c`;
            my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$jna\_split_CHR_$c", job_hold => $bgz_jid, cpu => "1", mem => "5", cluster_out => "$output/progress/$pre\_$uID\_$jna\_split_CHR$c.log");
            my $standardParams = Schedule::queuing(%stdParams);
            `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $BCFTOOLS/bcftools filter -r $CHR_PREFIX$c $vcf.gz -O v -o $vcf_dir/chrom_$c/$jna\_CHR$c.vcf`;

            %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$jna\_CHR$c\_MAF_UNPAIRED", job_hold => "$pre\_$uID\_$jna\_split_CHR_$c", cpu => "4", mem => "10", cluster_out => "$output/progress/$pre\_$uID\_$jna\_CHR$c\_MAF_UNPAIRED.log");
            $standardParams = Schedule::queuing(%stdParams);
            `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $Bin/generateMAF.pl -vcf $vcf_dir/chrom_$c/$jna\_CHR$c.vcf -species $species -config $config -caller $type $patientFile -align_dir $output/alignments -delete_temp`;
            `/bin/touch $output/progress/$pre\_$uID\_$jna\_CHR$c\_MAF_UNPAIRED.done`;
            push @all_jids, "$pre\_$uID\_$jna\_CHR$c\_MAF_UNPAIRED";
            push @chr_maf_jids, "$pre\_$uID\_$jna\_CHR$c\_MAF_UNPAIRED";
            push @vcf_files, "$vcf_dir/chrom_$c/$jna\_CHR$c.vcf";
        }
        #push @vcf_files, "$vcf_dir/chrom_$c/$jna\_CHR$c.vcf";
        #push @chr_maf_jids, "$pre\_$uID\_$jna\_CHR$c\_MAF_UNPAIRED";
    }
    
    my $jid_holds = join(",", @chr_maf_jids);
    my @merge_files = @vcf_files;
    s/vcf$/vcf_UNPAIRED_TCGA_MAF.txt/g for @merge_files;
    my $merge_files = join(" -i ", @merge_files);
    my @merge_jids;

    if(@chr_maf_jids){
        # MAKE A JOB HERE THAT WILL MERGE ALL THE MAF FILES FOR TCGA_MAF, TCGA_PORTAL_MAF, TCGA_PORTAL_MAF_fillout, and VEP_MAF
         my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$jna\_merge_TCGA_MAF", job_hold => "$jid_holds", cpu => "1", mem => "5", cluster_out => "$output/progress/$pre\_$uID\_$jna\_merge_TCGA_MAF.log");
        my $standardParams = Schedule::queuing(%stdParams);
        print "$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $PERL/perl $Bin/maf/mergeMaf.pl -i $merge_files -o $vcf_dir/$jna\_UNPAIRED_TCGA_MAF.txt\n";
        `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $PERL/perl $Bin/maf/mergeMaf.pl -i $merge_files -o $vcf_dir/$jna\_UNPAIRED_TCGA_MAF.txt`;
        push @merge_jids, "$pre\_$uID\_$jna\_merge_TCGA_MAF";

        $merge_files =~ s/UNPAIRED_TCGA_MAF.txt/UNPAIRED_TCGA_PORTAL_MAF.txt/g;
        %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$jna\_merge_TCGA_PORTAL_MAF", job_hold => "$jid_holds", cpu => "1", mem => "5", cluster_out => "$output/progress/$pre\_$uID\_$jna\_merge_TCGA_PORTAL_MAF.log");
        $standardParams = Schedule::queuing(%stdParams);
        print "$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $PERL/perl $Bin/maf/mergeMaf.pl -i $merge_files -o $vcf_dir/$jna\_UNPAIRED_TCGA_PORTAL_MAF.txt\n";
        `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $PERL/perl $Bin/maf/mergeMaf.pl -i $merge_files -o $vcf_dir/$jna\_UNPAIRED_TCGA_PORTAL_MAF.txt`;
        push @merge_jids, "$pre\_$uID\_$jna\_merge_TCGA_PORTAL_MAF";

        $merge_files =~ s/UNPAIRED_TCGA_PORTAL_MAF.txt/UNPAIRED_VEP_MAF.txt/g;
        %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$jna\_merge_VEP_MAF", job_hold => "$jid_holds", cpu => "1", mem => "5", cluster_out => "$output/progress/$pre\_$uID\_$jna\_merge_VEP_MAF.log");
        $standardParams = Schedule::queuing(%stdParams);
        print "$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $PERL/perl $Bin/maf/mergeMaf.pl -i $merge_files -o $vcf_dir/$jna\_UNPAIRED_VEP_MAF.txt\n";
        `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $PERL/perl $Bin/maf/mergeMaf.pl -i $merge_files -o $vcf_dir/$jna\_UNPAIRED_VEP_MAF.txt`;
        push @merge_jids, "$pre\_$uID\_$jna\_merge_VEP_MAF";

        if($patient){
            s/vcf_UNPAIRED_TCGA_MAF.txt$/vcf_UNPAIRED_TCGA_PORTAL_MAF_fillout.txt/g for @merge_files;
            $merge_files = join(" -i ", @merge_files);
            %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$jna\_merge_TCGA_PORTAL_MAF_fillout", job_hold => "$jid_holds", cpu => "1", mem => "5", cluster_out => "$output/progress/$pre\_$uID\_$jna\_merge_TCGA_PORTAL_MAF_fillout.log");
            $standardParams = Schedule::queuing(%stdParams);
            print "$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $PERL/perl $Bin/maf/mergeMaf.pl -i $merge_files -o $vcf_dir/$jna\_UNPAIRED_TCGA_PORTAL_MAF_fillout.txt\n";
            `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams $PERL/perl $Bin/maf/mergeMaf.pl -i $merge_files -o $vcf_dir/$jna\_UNPAIRED_TCGA_PORTAL_MAF_fillout.txt`;
            push @merge_jids, "$pre\_$uID\_$jna\_merge_TCGA_PORTAL_MAF_fillout";
        }

        #Now to clean up!
        my $merge_holds = join(",", @merge_jids);
        push @all_jids, "$merge_holds";
        my %stdParams = (scheduler => "$scheduler", job_name => "$pre\_$uID\_$jna\_cleanup", job_hold => "$merge_holds", cpu => "1", mem => "1", cluster_out => "$output/progress/$pre\_$uID\_$jna\_cleanup.log");
        $standardParams = Schedule::queuing(%stdParams);
        `$standardParams->{submit} $standardParams->{job_name} $standardParams->{job_hold} $standardParams->{cpu} $standardParams->{mem} $standardParams->{cluster_out} $additionalParams rm -rf $vcf_dir/chrom_* $vcf.gz $vcf.gz.csi`;
    }
}


