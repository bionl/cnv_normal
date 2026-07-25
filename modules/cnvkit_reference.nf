nextflow.enable.dsl = 2

process CNVKIT_REFERENCE {
    tag "build_pon"
    label 'process_medium'

    container 'quay.io/biocontainers/cnvkit:0.9.10--pyhdfd78af_0'
    publishDir "${params.outdir}/reference", mode: 'copy', overwrite: true

    input:
    path target_cnns
    path antitarget_cnns
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
