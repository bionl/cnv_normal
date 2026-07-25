#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

// ─────────────────────────────────────────────────────────────────────────────
//  Module imports
// ─────────────────────────────────────────────────────────────────────────────

include { CNVKIT_ACCESS                               } from './modules/cnvkit_access'
include { CNVKIT_TARGET                               } from './modules/cnvkit_target'
include { CNVKIT_COVERAGE_TARGET; CNVKIT_COVERAGE_ANTITARGET } from './modules/cnvkit_coverage'
include { CNVKIT_REFERENCE                            } from './modules/cnvkit_reference'

// ─────────────────────────────────────────────────────────────────────────────
//  Parameter defaults
// ─────────────────────────────────────────────────────────────────────────────

params.input               = null
params.fasta               = null
params.fasta_fai           = null
params.targets             = null
params.access              = null
params.annotate            = null
params.outdir              = 'results'
params.short_names         = true
params.target_avg_size     = 267
params.antitarget_avg_size = 500000
params.min_mapq            = 0
params.count_reads         = false

// ─────────────────────────────────────────────────────────────────────────────
//  Workflow
// ─────────────────────────────────────────────────────────────────────────────

workflow {

    if (!params.fasta)   error "Please provide --fasta"
    if (!params.input)   error "Please provide --input (samplesheet CSV)"
    if (!params.targets) error "Please provide --targets (capture BED)"

    ch_fasta = Channel.value(file(params.fasta))
    ch_fai   = Channel.value(params.fasta_fai ? file(params.fasta_fai) : file("${params.fasta}.fai"))

    ch_samples = Channel
        .fromPath(params.input)
        .splitCsv()
        .map { row -> [ [id: row[0]], file(row[1]), file(row[2]) ] }

    // 1. Access BED
    if (params.access) {
        ch_access = Channel.value(file(params.access))
    } else {
        CNVKIT_ACCESS(ch_fasta, ch_fai)
        ch_access = CNVKIT_ACCESS.out.access_bed
    }

    // 2. Target + antitarget BEDs
    CNVKIT_TARGET(Channel.value(file(params.targets)), ch_access)

    // 3. Per-sample coverage
    CNVKIT_COVERAGE_TARGET(
        ch_samples,
        CNVKIT_TARGET.out.target_bed,
        ch_fasta,
        ch_fai
    )

    CNVKIT_COVERAGE_ANTITARGET(
        ch_samples,
        CNVKIT_TARGET.out.antitarget_bed,
        ch_fasta,
        ch_fai
    )

    // 4. Build PoN reference
    CNVKIT_REFERENCE(
        CNVKIT_COVERAGE_TARGET.out.target_cnn.collect(),
        CNVKIT_COVERAGE_ANTITARGET.out.antitarget_cnn.collect(),
        ch_fasta,
        ch_fai
    )
}
