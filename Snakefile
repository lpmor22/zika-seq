import time
import subprocess
from cfg import config
import os

DEMUX_DIR = config['demux_dir']
BASECALLED_READS = config['basecalled_reads']
RAW_READS = config['raw_reads']
BUILD_DIR = config['build_dir']
PREFIX = config["prefix"]

def get_minion_analysis():
    call = "find %s -name \"*.fast5\" | head -n 1" % (config['raw_reads'])
    fname = subprocess.check_output(call,shell=True)
    if type(fname) != str:
        fname = str(fname)[2:-3]
    fname = fname.replace(config['raw_reads'],"")[1:]
    return fname

GET_MINION_ANALYSIS = get_minion_analysis()

rule all:
    params:
        build = BUILD_DIR
    input:
        "%s" % (BUILD_DIR)

def _get_basecall_config(wildcards):
    return config["basecall_config"]

rule basecall_guppy:
    params:
        cfg = _get_basecall_config
    input:
        raw = "%s" % (RAW_READS)
    output:
        directory("%s/pass" % (BASECALLED_READS))
    shell:
        "guppy_basecaller --cpu_threads_per_caller 12 --verbose_logs --qscore_filtering --input_path %s --save_path %s --records_per_fastq 0 --recursive --config {params.cfg}" % (RAW_READS, BASECALLED_READS)

def get_fastq_file():
    call = "find %s -name \"*.fast5\" | head -n 1" % (config['basecalled_reads']+"/pass")
    fname = subprocess.check_output(call,shell=True)
    if type(fname) != str:
        fname = str(fname)[2:-3]
    fname = fname.replace(config['basecalled_reads']+"/pass","")[1:]
    return fname

FASTQ = get_fastq_file()

rule demultiplex_guppy:
    input:
        rules.basecall_guppy.output
    output:
        directory("%s/guppy_demultiplex" % (BASECALLED_READS))
    shell:
        "guppy_barcoder --worker_threads 12 --input_path %s/pass/%s --save_path %s/guppy_demultiplex --recursive --verbose_logs --records_per_fastq 0 --require_barcodes_both_ends && tar -czvf %s/guppy_demultiplex/unclassified.tar.gz %s/guppy_demultiplex/unclassified && rm -rf %s/guppy_demultiplex/unclassified" % (BASECALLED_READS, FASTQ, BASECALLED_READS, BASECALLED_READS, BASECALLED_READS, BASECALLED_READS)

        rules.demultiplex_guppy.output
    output:
        directory("%s" % (DEMUX_DIR))
    shell:
        "porechop --input %s/guppy_demultiplex --threads 12 --barcode_dir %s --require_two_barcodes --check_reads 100000" % (BASECALLED_READS, DEMUX_DIR)

def _get_samples(wildcards):
    "Build a string of all samples that will be processed in a pipeline.py run"
    s = config['samples']
    samples = " ".join(s)
    return samples

rule pipeline:
    params:
        dimension=config['dimension'],
        samples=_get_samples,
        raw=config['raw_reads'],
        build=BUILD_DIR,
        basecalled_reads=config['basecalled_reads'],
	reference_genome=config['reference_genome'],
	primer_scheme=config['primer_scheme']
    input:
        rules.demultiplex_porechop.output
    output:
        directory("%s" % (BUILD_DIR))
    shell:
        "mkdir build/ && python pipeline/scripts/pipeline.py --samples {params.samples} --dimension {params.dimension} --raw_reads {params.raw} --build_dir {params.build} --basecalled_reads {params.basecalled_reads} --reference_genome {params.reference_genome} --primer_scheme {params.primer_scheme}"
