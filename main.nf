#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

// ============================================================
//  CNVkit Panel of Normals (PoN) pipeline
//  Input  : 5 normal BAMs from 1000 Genomes
//  Output : reference.cnn  →  drop into Sarek --cnvkit_reference
// ============================================================

// ---------- parameter defaults ----------
params.input        = null          // samplesheet CSV  (sample,bam,bai)
params.fasta        = null          // reference genome  (must match BAMs)
params.fasta_fai    = null          // .fai index
params.targets      = null          // BED of captured regions (null = WGS)
params.antitargets  = null          // optional pre-computed antitarget BED
params.outdir       = "results"
params.access       = null          // cnvkit access BED (auto-generated if null)
params.annotate     = null          // optional refFlat / gene annotation BED
params.short_names  = true          // shorten region names in output
params.target_avg_size   = 267      // cnvkit autobin target average size
params.antitarget_avg_size = 500000 // cnvkit autobin antitarget average size
params.min_mapq     = 0             // minimum mapping quality for coverage
params.count_reads  = false         // use read-count instead of average depth

// ---------- help ----------
if (params.help) {
    log.info """
    ╔══════════════════════════════════════════════════════╗
    ║        CNVkit Panel of Normals – Nextflow DSL2       ║
    ╚══════════════════════════════════════════════════════╝

    Usage:
        nextflow run main.nf \\
            --input      samplesheet.csv \\
            --fasta      /path/to/genome.fa \\
            --targets    /path/to/capture.bed \\   # omit for WGS
            --outdir     results

    Samplesheet format (CSV, no header):
        sample_id,/abs/path/to/sample.bam,/abs/path/to/sample.bam.bai

    Outputs (in --outdir):
        reference.cnn          ← use with Sarek --cnvkit_reference
        *.targetcoverage.cnn
        *.antitargetcoverage.cnn
    """.stripIndent()
    exit 0
}

// ---------- validate ----------
if (!params.fasta)  error "Please provide --fasta"
if (!params.input)  error "Please provide --input samplesheet CSV"

// ============================================================
//  PROCESSES
// ============================================================

// 1. Build accessible-genome BED (skip if user supplies --access)
process CNVKIT_ACCESS {
    tag "access"
    label 'process_low'

    container 'etal/cnvkit:latest'
    publishDir "${params.outdir}/reference", mode: 'copy', overwrite: true

    input:
    path fasta
    path fai

    output:
    path "access.bed", emit: access_bed

    script:
    """
    cnvkit.py access \\
        ${fasta} \\
        -o access.bed
    """
}

// 2. Auto-bin: derive target + antitarget BEDs from capture BED (WES)
//    For WGS, skip this and go straight to coverage with --method wgs
process CNVKIT_AUTOBIN {
    tag "autobin"
    label 'process_low'

    container 'etal/cnvkit:latest'
    publishDir "${params.outdir}/reference", mode: 'copy', overwrite: true

    input:
    path targets_bed
    path access_bed
    path fasta
    path fai

    output:
    path "*.target.bed",     emit: target_bed
    path "*.antitarget.bed", emit: antitarget_bed

    script:
    def annotate_opt = params.annotate ? "--annotate ${params.annotate}" : ""
    def short_opt    = params.short_names ? "--short-names" : ""
    """
    cnvkit.py autobin \\
        ${targets_bed} \\
        -m hybrid \\
        --access ${access_bed} \\
        --target-avg-size   ${params.target_avg_size} \\
        --antitarget-avg-size ${params.antitarget_avg_size} \\
        ${annotate_opt} \\
        ${short_opt} \\
        -t targets_auto.target.bed \\
        -g targets_auto.antitarget.bed
    """
}

// 3. Per-sample target coverage
process CNVKIT_COVERAGE_TARGET {
    tag "${meta.id} – target"
    label 'process_medium'

    container 'etal/cnvkit:latest'
    publishDir "${params.outdir}/coverage", mode: 'copy', overwrite: true

    input:
    tuple val(meta), path(bam), path(bai)
    path target_bed
    path fasta
    path fai

    output:
    path "${meta.id}.targetcoverage.cnn", emit: target_cnn

    script:
    def mapq_opt  = params.min_mapq > 0   ? "--min-mapq ${params.min_mapq}" : ""
    def count_opt = params.count_reads     ? "--count"                       : ""
    """
    cnvkit.py coverage \\
        ${bam} \\
        ${target_bed} \\
        ${mapq_opt} \\
        ${count_opt} \\
        -o ${meta.id}.targetcoverage.cnn
    """
}

// 4. Per-sample antitarget coverage
process CNVKIT_COVERAGE_ANTITARGET {
    tag "${meta.id} – antitarget"
    label 'process_medium'

    container 'etal/cnvkit:latest'
    publishDir "${params.outdir}/coverage", mode: 'copy', overwrite: true

    input:
    tuple val(meta), path(bam), path(bai)
    path antitarget_bed
    path fasta
    path fai

    output:
    path "${meta.id}.antitargetcoverage.cnn", emit: antitarget_cnn

    script:
    def mapq_opt  = params.min_mapq > 0 ? "--min-mapq ${params.min_mapq}" : ""
    def count_opt = params.count_reads   ? "--count"                       : ""
    """
    cnvkit.py coverage \\
        ${bam} \\
        ${antitarget_bed} \\
        ${mapq_opt} \\
        ${count_opt} \\
        -o ${meta.id}.antitargetcoverage.cnn
    """
}

// 5. Build the PoN reference from all normals
process CNVKIT_REFERENCE {
    tag "build_pon"
    label 'process_medium'

    container 'etal/cnvkit:latest'
    publishDir "${params.outdir}/reference", mode: 'copy', overwrite: true

    input:
    path target_cnns      // collected list
    path antitarget_cnns  // collected list
    path fasta
    path fai

    output:
    path "reference.cnn", emit: reference_cnn

    script:
    """
    cnvkit.py reference \\
        ${target_cnns} \\
        ${antitarget_cnns} \\
        --fasta ${fasta} \\
        -o reference.cnn
    """
}

// 6. QC: plot per-sample coverage scatter (optional but useful)
process CNVKIT_SCATTER_QC {
    tag "${sample_id}"
    label 'process_low'

    container 'etal/cnvkit:latest'
    publishDir "${params.outdir}/qc/scatter", mode: 'copy', overwrite: true

    input:
    tuple val(sample_id), path(target_cnn), path(antitarget_cnn)
    path reference_cnn

    output:
    path "${sample_id}_scatter.pdf", optional: true

    script:
    """
    # First fix the coverage to log2 ratios vs the new reference
    cnvkit.py fix \\
        ${target_cnn} \\
        ${antitarget_cnn} \\
        ${reference_cnn} \\
        -o ${sample_id}.cnr

    cnvkit.py scatter \\
        ${sample_id}.cnr \\
        -o ${sample_id}_scatter.pdf || true
    """
}

// ============================================================
//  WORKFLOW
// ============================================================

workflow {

    // --- input channel from CSV (sample,bam,bai) ---
    ch_samples = Channel
        .fromPath(params.input)
        .splitCsv()
        .map { row ->
            def meta = [id: row[0]]
            [ meta, file(row[1]), file(row[2]) ]
        }

    ch_fasta = file(params.fasta)
    ch_fai   = params.fasta_fai ? file(params.fasta_fai) : file("${params.fasta}.fai")

    // --- access BED ---
    if (params.access) {
        ch_access = Channel.value(file(params.access))
    } else {
        CNVKIT_ACCESS(ch_fasta, ch_fai)
        ch_access = CNVKIT_ACCESS.out.access_bed
    }

    // --- target / antitarget BEDs ---
    if (params.targets) {
        CNVKIT_AUTOBIN(
            file(params.targets),
            ch_access,
            ch_fasta,
            ch_fai
        )
        ch_target_bed     = CNVKIT_AUTOBIN.out.target_bed
        ch_antitarget_bed = CNVKIT_AUTOBIN.out.antitarget_bed
    } else {
        // WGS mode: cnvkit.py access output is both target & antitarget
        error "WGS mode: please supply --targets (WES BED) or adapt autobin for wgs method"
    }

    // --- per-sample coverage ---
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

    // --- collect all coverage CNNs ---
    ch_all_target_cnns     = CNVKIT_COVERAGE_TARGET.out.target_cnn.collect()
    ch_all_antitarget_cnns = CNVKIT_COVERAGE_ANTITARGET.out.antitarget_cnn.collect()

    // --- build reference ---
    CNVKIT_REFERENCE(
        ch_all_target_cnns,
        ch_all_antitarget_cnns,
        ch_fasta,
        ch_fai
    )

    // --- QC scatter plots ---
    ch_cov_pairs = CNVKIT_COVERAGE_TARGET.out.target_cnn
        .map { cnn -> [ cnn.baseName.replaceAll(/\.targetcoverage$/, ""), cnn ] }
        .join(
            CNVKIT_COVERAGE_ANTITARGET.out.antitarget_cnn
                .map { cnn -> [ cnn.baseName.replaceAll(/\.antitargetcoverage$/, ""), cnn ] }
        )

    CNVKIT_SCATTER_QC(
        ch_cov_pairs,
        CNVKIT_REFERENCE.out.reference_cnn
    )

    // --- final message ---
    CNVKIT_REFERENCE.out.reference_cnn.view { ref ->
        "\n✅  PoN reference built: ${ref}\n   → Use with Sarek: --cnvkit_reference ${params.outdir}/reference/reference.cnn\n"
    }
}
