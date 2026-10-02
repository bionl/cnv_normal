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
    """
    # Symlink all alignment files and their indices so pysam can find them
    for aln in ${crams}; do
        base=\$(basename \$aln)
        ln -sf \$aln \$base
    done
    for idx in ${crais}; do
        base=\$(basename \$idx)
        ln -sf \$idx \$base
    done

    # Collect BAMs and/or CRAMs (whichever were provided)
    ALN_FILES=\$(ls *.bam *.cram 2>/dev/null | tr '\\n' ' ')

    cnvkit.py autobin \\
        \$ALN_FILES \\
        -m wes \\
        -g ${access_bed} \\
        -f ${fasta} \\
        ${annotate_opt} \\
        --target-output-bed   targets.target.bed \\
        --antitarget-output-bed targets.antitarget.bed
    """
}
