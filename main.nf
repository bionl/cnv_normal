#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

// ─────────────────────────────────────────────────────────────────────────────
//  Module imports
// ─────────────────────────────────────────────────────────────────────────────

include { CNVKIT_ACCESS                               } from './modules/cnvkit_access'
include { CNVKIT_AUTOBIN                              } from './modules/cnvkit_autobin'
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

    if (!params.fasta) error "Please provide --fasta"
    if (!params.input) error "Please provide --input (samplesheet CSV)"

    ch_fasta = Channel.value(file(params.fasta))
    ch_fai   = Channel.value(params.fasta_fai ? file(params.fasta_fai) : file("${params.fasta}.fai"))

    ch_samples = Channel
        .fromPath(params.input)
        .splitCsv()
        .map { row ->
            def meta = [id: row[0]]
            def cram = file(row[1], checkIfExists: false)
            def crai = file(row[2], checkIfExists: false)
            [ meta, cram, crai ]
        }

    // 1. Access BED
    if (params.access) {
        ch_access = Channel.value(file(params.access))
    } else {
        CNVKIT_ACCESS(ch_fasta, ch_fai)
        ch_access = CNVKIT_ACCESS.out.access_bed
    }

    // 2. Target + antitarget BEDs
    //    — if a capture BED is provided, use cnvkit target/antitarget
    //    — otherwise infer target regions from the CRAMs via autobin
    if (params.targets) {
        CNVKIT_TARGET(Channel.value(file(params.targets)), ch_access)
        ch_target_bed    = CNVKIT_TARGET.out.target_bed
        ch_antitarget_bed = CNVKIT_TARGET.out.antitarget_bed
    } else {
        log.warn "No --targets BED provided — falling back to cnvkit autobin (target regions inferred from CRAMs)"
        CNVKIT_AUTOBIN(
            ch_samples.map { meta, cram, crai -> cram }.collect(),
            ch_samples.map { meta, cram, crai -> crai }.collect(),
            ch_access,
            ch_fasta,
            ch_fai
        )
        ch_target_bed    = CNVKIT_AUTOBIN.out.target_bed
        ch_antitarget_bed = CNVKIT_AUTOBIN.out.antitarget_bed
    }

    // 3. Per-sample coverage
    CNVKIT_COVERAGE_TARGET(
        ch_samples,
        ch_target_bed,
        ch_fasta,
        ch_fai
    )

    CNVKIT_COVERAGE_ANTITARGET(
        ch_samples,
        ch_antitarget_bed,
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
