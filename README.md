# CNVkit Panel of Normals – Nextflow Pipeline

Builds a `reference.cnn` from a pool of normal BAMs (here: 5 × 1000 Genomes samples)
to replace Sarek's flat reference and remove coverage bias from your GIAB benchmarking run.

---

## Background

Sarek's built-in CNVkit workflow creates a **flat reference** when no PoN is supplied —
every bin gets a baseline of 0 log₂ ratio. This inflates false-positives in GC-rich /
mappability-poor regions. By providing a `reference.cnn` built from population normals
that match your sequencing protocol you correct for:

- GC content bias
- Systematic coverage drops at repeat / low-complexity regions
- Library-prep and capture kit artefacts

---

## Requirements

| Tool | Version |
|------|---------|
| Nextflow | ≥ 23.04 |
| Docker **or** Singularity | any recent |
| CNVkit image | `etal/cnvkit:latest` (pulled automatically) |

---

## Input files

### 1. Samplesheet (`samplesheet.csv`)

Plain CSV, **no header**, three columns:

```
sample_id,/absolute/path/to/sample.bam,/absolute/path/to/sample.bam.bai
```

Example:

```csv
NA12878,/data/1000g/NA12878.bam,/data/1000g/NA12878.bam.bai
NA12877,/data/1000g/NA12877.bam,/data/1000g/NA12877.bam.bai
NA12879,/data/1000g/NA12879.bam,/data/1000g/NA12879.bam.bai
NA12880,/data/1000g/NA12880.bam,/data/1000g/NA12880.bam.bai
NA12881,/data/1000g/NA12881.bam,/data/1000g/NA12881.bam.bai
```

### 2. Reference genome

Must be the **same reference** used to align the 1000G BAMs **and** your GIAB sample
(e.g. GRCh38 `Homo_sapiens_assembly38.fasta`).

### 3. Capture BED (WES only)

The BED file describing your exome / panel capture regions.
Use the kit-specific BED that **matches your Sarek run**.

---

## Usage

### Minimal run (WES, Docker)

```bash
nextflow run main.nf \
    -profile docker \
    --input     samplesheet.csv \
    --fasta     /ref/GRCh38/Homo_sapiens_assembly38.fasta \
    --targets   /ref/capture/SureSelect_All_Exon_V7_hg38.bed \
    --outdir    results
```

### With Singularity on a Slurm cluster

```bash
nextflow run main.nf \
    -profile slurm,singularity \
    --input     samplesheet.csv \
    --fasta     /ref/GRCh38/Homo_sapiens_assembly38.fasta \
    --targets   /ref/capture/SureSelect_All_Exon_V7_hg38.bed \
    --outdir    results \
    -resume
```

### Pre-computed access BED (speeds up reruns)

```bash
nextflow run main.nf \
    -profile docker \
    --input   samplesheet.csv \
    --fasta   /ref/GRCh38/Homo_sapiens_assembly38.fasta \
    --targets /ref/capture/SureSelect_All_Exon_V7_hg38.bed \
    --access  results/reference/access.bed \   # from a previous run
    --outdir  results
```

---

## Outputs

```
results/
├── reference/
│   ├── access.bed                   ← mappable-genome BED
│   ├── targets_auto.target.bed      ← binned target regions
│   ├── targets_auto.antitarget.bed  ← binned off-target regions
│   └── reference.cnn                ← ← ← THE FILE YOU NEED
├── coverage/
│   ├── NA12878.targetcoverage.cnn
│   ├── NA12878.antitargetcoverage.cnn
│   └── ...
├── qc/
│   └── scatter/
│       └── NA12878_scatter.pdf      ← per-sample QC plot
└── pipeline_info/
    ├── timeline_*.html
    ├── report_*.html
    └── trace_*.txt
```

---

## Integrating with Sarek

Pass `reference.cnn` via the `--cnvkit_reference` parameter:

```bash
nextflow run nf-core/sarek \
    -profile docker \
    --input       sarek_samplesheet.csv \
    --genome      GATK.GRCh38 \
    --tools       cnvkit \
    --cnvkit_reference  /path/to/results/reference/reference.cnn \
    --outdir      sarek_results
```

> **Note:** Sarek ≥ 3.2 supports `--cnvkit_reference` directly.
> For older versions you can symlink the file into Sarek's `assets/` directory or
> patch the `cnvkit/batch` process in your local copy.

---

## Key parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--input` | — | Samplesheet CSV (required) |
| `--fasta` | — | Reference FASTA (required) |
| `--targets` | — | Capture BED (required for WES) |
| `--access` | auto | Pre-computed access BED |
| `--annotate` | — | refFlat gene annotation for bin labelling |
| `--target_avg_size` | 267 | Target bin size (bp) |
| `--antitarget_avg_size` | 500000 | Antitarget bin size (bp) |
| `--min_mapq` | 0 | Min mapping quality for coverage |
| `--count_reads` | false | Use read counts instead of avg depth |
| `--outdir` | results | Output directory |

---

## Pipeline steps

```
samplesheet.csv
      │
      ▼
[CNVKIT_ACCESS]           builds accessible-genome BED from FASTA
      │
      ▼
[CNVKIT_AUTOBIN]          derives optimal target + antitarget bin BEDs
      │
      ├──────────────────────────────────┐
      ▼                                  ▼
[CNVKIT_COVERAGE_TARGET]   [CNVKIT_COVERAGE_ANTITARGET]   (× N samples, parallel)
      │                                  │
      └──────────────┬───────────────────┘
                     ▼
             [CNVKIT_REFERENCE]          merges all coverage → reference.cnn
                     │
                     ▼
             [CNVKIT_SCATTER_QC]         QC scatter per sample
```

---

## Troubleshooting

**"reference.cnn has very few bins"** – your `--targets` BED and `--fasta` may be on
different genome builds (e.g. chr-prefixed vs non-prefixed). Ensure they match.

**Coverage all zeros** – check BAI index is present and co-located with the BAM.
Run `samtools quickcheck sample.bam` to verify file integrity.

**Sarek ignores `--cnvkit_reference`** – confirm you are on Sarek ≥ 3.2 and that the
path is absolute, not relative.
