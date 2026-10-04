nextflow.enable.dsl = 2

process CNVKIT_AUTOBIN {
    tag "autobin"
    label 'process_medium'

    container 'quay.io/biocontainers/cnvkit:0.9.10--pyhdfd78af_0'
    publishDir "${params.outdir}/reference", mode: 'copy', overwrite: true

    input:
    path crams
    path crais
    path access_bed
    path fasta
    path fai

    output:
    path "targets.target.bed",     emit: target_bed
    path "targets.antitarget.bed", emit: antitarget_bed

    script:
    def annotate_opt = params.annotate ? "--annotate ${params.annotate}" : ""
    // Nextflow stages all files into the work dir — BAMs/CRAMs and their
    // indices land side-by-side, so no symlinks are needed here.
    """
    cnvkit.py autobin \\
        ${crams} \\
        -m wgs \\
        -g ${access_bed} \\
        -f ${fasta} \\
        ${annotate_opt} \\
        --target-output-bed     targets.target.bed \\
        --antitarget-output-bed targets.antitarget.bed
    """
}
