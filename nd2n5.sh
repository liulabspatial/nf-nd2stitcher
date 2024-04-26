#!/bin/bash
usage() {
	echo "Usage: nd2n5.sh [OPTION]... [FILE]"
	echo "ND2 Stitching Pipeline"
	echo
	echo "Options:"
	echo "  -i, --input		    path to an input nd2 file"
	echo "  -o, --outdir    	path to an output directory"
	echo "  -d, --dapi		    channel id of a dapi channel."
    echo "  -t, --thread    	number of threads for non-spark processes"
    echo "  -w, --worker    	number of workers for spark processes"
    echo "  -c, --core    	    number of cores per worker for spark processes"
    echo "  -p, --prestitch	    do not perform image fusion"
    echo "  -f, --fusionOnly	perform only image fusion"
	echo "  --oneTileWins		use the one-tile-wins strategy for stitching"
    echo "  -r, --resume    	resume a workflow execution"
	echo "  -h, --help		    display this help and exit"
	exit 1
}

DAPI=0
MODEL="/nrs/scicompsoft/kawaset/Liu/ESCell60X"
MINSEGSIZE=1200
DIAMETER=40

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
		'-d'|'--dapi' )
			if [[ -z "$2" ]] || [[ "$2" =~ ^-+ ]]; then
				echo "$PROGNAME: option requires an argument -- $1" 1>&2
				exit 1
			fi
			DAPI="$2"
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

RAND=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13;)

NXFTMPDIR="/scratch/$USER/$RAND/nextflow_temp"
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

nextflow run ./nd2n5/nd2n5.nf -profile lsf $RESUME --runtime_opts "--env TMPDIR=$NXFTMPDIR -B $INPUTDIR -B /scratch" --dapi_channel \"$DAPI\" --inputPath "$INPUTND2" --outputPath "$OUTDIR" $PRESTITCH $FUSIONONLY $ONETILEWINS $THREADNUM $WORKERNUM $CORENUM
