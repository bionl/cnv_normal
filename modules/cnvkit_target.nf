nextflow.enable.dsl = 2

process CNVKIT_TARGET {
    tag "target"
    label 'process_low'

    container 'quay.io/biocontainers/cnvkit:0.9.10--pyhdfd78af_0'
    publishDir "${params.outdir}/reference", mode: 'copy', overwrite: true

    input:
    path targets_bed
    path access_bed

    output:
    path "targets.target.bed",     emit: target_bed
    path "targets.antitarget.bed", emit: antitarget_bed

    script:
    def annotate_opt = params.annotate   ? "--annotate ${params.annotate}" : ""
    def short_opt    = params.short_names ? "--short-names"                 : ""
    """
    cnvkit.py target \\
        ${targets_bed} \\
        --access ${access_bed} \\
        --avg-size ${params.target_avg_size} \\
        ${annotate_opt} \\
        ${short_opt} \\
        -o targets.target.bed

    cnvkit.py antitarget \\
        ${targets_bed} \\
        --access ${access_bed} \\
        --avg-size ${params.antitarget_avg_size} \\
        -o targets.antitarget.bed
    """
}
