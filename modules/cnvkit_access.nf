nextflow.enable.dsl = 2

process CNVKIT_ACCESS {
    tag "access"
    label 'process_low'

    container 'quay.io/biocontainers/cnvkit:0.9.10--pyhdfd78af_0'
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
