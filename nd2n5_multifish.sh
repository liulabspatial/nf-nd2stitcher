#!/bin/bash

usage() {
	echo "Usage: nd2n5_multifish.sh [OPTION]... [FILE]"
	echo "ND2-to-N5 converter"
	echo
	echo "Options:"
	echo "  -i, --input		    path to an input nd2 file"
	echo "  -o, --outdir    	path to an output directory"
	echo "  -b, --bg		    path to a background image for background subtraction"
	echo "  -d, --dapi		    channel id of a dapi channel."
	echo "  -m, --model			path to a cell pose model"
    echo "  -t, --thread    	number of threads for non-spark processes"
    echo "  -w, --worker    	number of workers for spark processes"
    echo "  -c, --core    	    number of cores per worker for spark processes"
    echo "  -p, --prestitch	    do not perform image fusion"
    echo "  -f, --fusionOnly	perform only image fusion"
	echo "  --oneTileWins		use the one-tile-wins strategy for stitching"
    echo "  -r, --resume    	resume a workflow execution"
	echo "  -h, --help		    display this help and exit"
	echo "example: ./warpswc.sh -c /opt/local/lib/cmtk/bin -s JFRC2010_20x -t JFRC2013_20x input.swc > output.swc"
	exit 1
}

DAPI=0
MODEL="/nrs/scicompsoft/kawaset/Liu/ESCell60X"

for OPT in "$@"
do
	case "$OPT" in
		'-h'|'--help' )
			usage
			exit 1
			;;
		'-i'|'--input' )
			if [[ -z "$2" ]] || [[ "$2" =~ ^-+ ]]; then
				echo "$PROGNAME: option requires an argument -- $1" 1>&2
				exit 1
			fi
			INPUTND2="$2"
			shift 2
			;;
		'-o'|'--outdir' )
			if [[ -z "$2" ]] || [[ "$2" =~ ^-+ ]]; then
				echo "$PROGNAME: option requires an argument -- $1" 1>&2
				exit 1
			fi
			OUTDIR="$2"
			shift 2
			;;
		'-b'|'--bg' )
			if [[ -z "$2" ]] || [[ "$2" =~ ^-+ ]]; then
				echo "$PROGNAME: option requires an argument -- $1" 1>&2
				exit 1
			fi
			BGIMG="$2"
			shift 2
			;;
		'-d'|'--dapi' )
			if [[ -z "$2" ]] || [[ "$2" =~ ^-+ ]]; then
				echo "$PROGNAME: option requires an argument -- $1" 1>&2
				exit 1
			fi
			DAPI="$2"
			shift 2
			;;
		'-m'|'--model' )
			if [[ -z "$2" ]] || [[ "$2" =~ ^-+ ]]; then
				echo "$PROGNAME: option requires an argument -- $1" 1>&2
				exit 1
			fi
			MODEL="$2"
			shift 2
			;;
        '-t'|'--thread' )
			if [[ -z "$2" ]] || [[ "$2" =~ ^-+ ]]; then
				echo "$PROGNAME: option requires an argument -- $1" 1>&2
				exit 1
			fi
			THREADNUM="--cpus $2"
			shift 2
			;;
        '-w'|'--worker' )
			if [[ -z "$2" ]] || [[ "$2" =~ ^-+ ]]; then
				echo "$PROGNAME: option requires an argument -- $1" 1>&2
				exit 1
			fi
			WORKERNUM="--spark_workers $2"
			MFWORKERNUM="--workers $2"
			RSWORKERNUM="--rsfish_workers $2"
			shift 2
			;;
        '-c'|'--core' )
			if [[ -z "$2" ]] || [[ "$2" =~ ^-+ ]]; then
				echo "$PROGNAME: option requires an argument -- $1" 1>&2
				exit 1
			fi
			CORENUM="--spark_worker_cores $2"
			MFCORENUM="--worker_cores $2"
			RSCORENUM="--rsfish_worker_cores $2"
			shift 2
			;;
		'-p'|'--prestitch' )
			PRESTITCH="--prestitch"
			shift 1
			;;
        '-f'|'--fusionOnly' )
			FUSIONONLY="--fusionOnly"
			shift 1
			;;
		'--oneTileWins' )
			ONETILEWINS="--oneTileWins"
			shift 1
			;;
        '-r'|'--resume' )
			RESUME="-resume"
			shift 1
			;;
		'--'|'-' )
			shift 1
			param+=( "$@" )
			break
			;;
		-*)
			echo "$PROGNAME: illegal option -- '$(echo $1 | sed 's/^-*//')'" 1>&2
			exit 1
			;;
		*)
			if [[ ! -z "$1" ]] && [[ ! "$1" =~ ^-+ ]]; then
				#param=( ${param[@]} "$1" )
				param+=( "$1" )
				shift 1
			fi
		;;
	esac
done

INPUTDIR=$(dirname "$INPUTND2")
BGDIR=$(dirname "$BGIMG")

NXFTMPDIR="$OUTDIR/nextflow_temp"
if [ ! -d "$NXFTMPDIR" ]; then
    mkdir -p "$NXFTMPDIR"
    echo "Directory created: $NXFTMPDIR"
else
    echo "Directory already exists: $NXFTMPDIR"
fi

export TMPDIR="$NXFTMPDIR"
export NXF_TEMP="$NXFTMPDIR"
export PATH="/groups/scicompsoft/scicompsoft/kawaset_temp:$PATH"
export NXF_JAVA_HOME="/groups/scicompsoft/scicompsoft/kawaset_temp/tools/jdk-17" 
cd /groups/scicompsoft/scicompsoft/kawaset_temp/nd2n5

nextflow run ./nd2n5/nd2n5.nf -profile lsf $RESUME --runtime_opts "--env TMPDIR=$NXFTMPDIR -B $INPUTDIR -B $BGDIR -B /scratch" --inputPath "$INPUTND2" --outputPath "$OUTDIR" --bgimg "$BGIMG" $PRESTITCH $FUSIONONLY $ONETILEWINS $THREADNUM $WORKERNUM $CORENUM

SEARCH_DIR="$OUTDIR/easi"
NUM_TIMEPOINTS=$(($(find "$SEARCH_DIR" -maxdepth 1 -type d | wc -l) - 1))


MULTIFISHDIR="/groups/scicompsoft/home/kawaset/multifish2/multifish"
cd $MULTIFISHDIR

for (( i=0; i<NUM_TIMEPOINTS; i++ )); do
	# Directory to be searched
	N5_DIR="$OUTDIR/easi/dataset-t$i/stitching/export.n5"
	# Find directories, remove base path, and combine into comma-separated string
	CH_NAMES=$(find "$N5_DIR" -maxdepth 1 -mindepth 1 -type d -print | xargs -n 1 basename | tr '\n' ',' | sed 's/,$//')

	SPOT_DIR="$OUTDIR/easi/dataset-t$i/spots"
	if [ ! -d "$SPOT_DIR" ]; then
    	mkdir -p "$SPOT_DIR"
    	echo "Directory created: $SPOT_DIR"
	else
    	echo "Directory already exists: $SPOT_DIR"
	fi
	find "$N5_DIR" -maxdepth 1 -mindepth 1 -type d | while read dir; do
    	ch_name=$(basename "$dir")
    	newfile="$SPOT_DIR/spots_$ch_name.txt"
		newfile_rs="$SPOT_DIR/spots_rsfish_$ch_name.csv"
		echo "0.0,0.0,0.0,0.0" > $newfile
		echo "x,y,z,t,c,intensity" > $newfile_rs
		echo "0.0,0.0,0.0,1,1,0.0" >> $newfile_rs
	done

	COMMON_PARAMS="-dump-channels \
        -profile lsf \
        --runtime_opts \"--env TMPDIR=$NXFTMPDIR --env ITK_THREADS=32 -B /nrs/scicompsoft/kawaset/Liu -B $INPUTDIR -B $BGDIR -B $OUTDIR -B /scratch\" \
        --lsf_opts \"-P scicompsoft\" \
        $MFWORKERNUM \
        $MFCORENUM \
        --spark_work_dir \"$PWD/local\" \
        --data_dir \"$OUTDIR\" \
        --output_dir \"$OUTDIR/easi\" \
        --acq_names \"dataset-t$i\" \
        --ref_acq \"dataset-t0\" \
        --channels \"$CH_NAMES\" \
        --dapi_channel \"c$DAPI\" \
		--spot_extraction_scale \"s0\" \
		--aff_scale \"s3\" \
		--def_scale \"s1\" \
        --segmentation_scale \"s1\" \
        --segmentation_cpus 20 \
        --segmentation_memory '250 G' \
		--min_segsize 1200 \
		--diameter 40 \
        --skip \"$SKIP\" \
        --use_rsfish \
        --rsfish_anisotropy 1.0 \
        --rsfish_max 512 \
        --measure_intensities_cpus 48 \
        --measure_intensities_memory '700 G' \
        --assign_spots_cpus 48 \
        --assign_spots_memory '700 G' \
        --segmentation_model_dir \"$MODEL\" \"$@\""

	if [ $i == 0 ]; then
    	SKIP="stitching,spot_extraction,warp_spots,measure_intensities,assign_spots"
		RSFISH_CLUSTER_SETTINGS="$RSWORKERNUM $RSCORENUM --rsfish_gb_per_core 15"
		eval "nextflow run ./main.nf $COMMON_PARAMS --skip \"$SKIP\" $RSFISH_CLUSTER_SETTINGS"
	else
    	SKIP="stitching,segmentation"
		RSFISH_CLUSTER_SETTINGS="$RSWORKERNUM $RSCORENUM --rsfish_gb_per_core 15"
		bsub -n 1 -W 24:00 -o $OUTDIR/mulifish_log_t$i.txt -P scicompsoft "./main.nf -c $MULTIFISHDIR/nextflow_no_nv.config $COMMON_PARAMS --skip \"$SKIP\" $RSFISH_CLUSTER_SETTINGS"
		#eval "nextflow run ./main.nf -c $MULTIFISHDIR/nextflow_no_nv.config $COMMON_PARAMS --skip \"$SKIP\" $RSFISH_CLUSTER_SETTINGS"
	fi
	
	
done