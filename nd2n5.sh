#!/bin/bash

usage() {
	echo "Usage: nd2n5.sh [OPTION]... [FILE]"
	echo "ND2-to-N5 converter"
	echo
	echo "Options:"
	echo "  -i, --input		    path to an input nd2 file"
	echo "  -o, --outdir    	path to an output directory"
	echo "  -b, --bg		    path to a background image for background subtraction"
	echo "  -d, --dapi		    channel id of a dapi channel."
    echo "  -t, --thread    	number of threads for non-spark processes"
    echo "  -w, --worker    	number of workers for spark processes"
    echo "  -c, --core    	    number of cores per worker for spark processes"
    echo "  -p, --prestitch	    do not perform image fusion"
    echo "  -f, --fusionOnly	perform only image fusion"
    echo "  -r, --resume    	resume a workflow execution"
	echo "  -h, --help		    display this help and exit"
	echo "example: ./warpswc.sh -c /opt/local/lib/cmtk/bin -s JFRC2010_20x -t JFRC2013_20x input.swc > output.swc"
	exit 1
}

DAPI=0

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
			shift 2
			;;
        '-c'|'--core' )
			if [[ -z "$2" ]] || [[ "$2" =~ ^-+ ]]; then
				echo "$PROGNAME: option requires an argument -- $1" 1>&2
				exit 1
			fi
			CORENUM="--spark_worker_cores $2"
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

export PATH="/groups/scicompsoft/scicompsoft/kawaset_temp:$PATH"
export NXF_JAVA_HOME="/groups/scicompsoft/scicompsoft/kawaset_temp/tools/jdk-17" 
cd /groups/scicompsoft/scicompsoft/kawaset_temp/nd2n5

/nrs/scicompsoft/kawaset/Liu/nextflow run ./nd2n5/nd2n5.nf -profile lsf $RESUME --runtime_opts "-B $INPUTDIR -B $BGDIR -B /scratch" --inputPath "$INPUTND2" --outputPath "$OUTDIR" --bgimg "$BGIMG" $PRESTITCH $FUSIONONLY $THREADNUM $WORKERNUM $CORENUM
