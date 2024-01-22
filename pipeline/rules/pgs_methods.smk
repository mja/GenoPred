# Create PC score files specific to each population
rule ref_pca_i:
  input:
    rules.get_dependencies.output
  output:
    "resources/data/ref/pc_score_files/{population}/ref-{population}-pcs.EUR.scale"
  conda:
    "../envs/analysis.yaml",
  params:
    testing=config["testing"]
  shell:
    "Rscript ../Scripts/ref_pca/ref_pca.R \
      --ref_plink_chr resources/data/ref/ref.chr \
      --ref_keep resources/data/ref/keep_files/{wildcards.population}.keep \
      --pop_data resources/data/ref/ref.pop.txt \
      --output resources/data/ref/pc_score_files/{wildcards.population}/ref-{wildcards.population}-pcs \
      --test {params.testing}"

populations=["AFR","AMR","EAS","EUR","SAS"]

rule ref_pca:
  input: expand("resources/data/ref/pc_score_files/{population}/ref-{population}-pcs.EUR.scale", population=populations)

##
# QC and format GWAS summary statistics
##

if 'gwas_list' in config:
  gwas_list_df = pd.read_table(config["gwas_list"], sep=r'\s+')
else:
  gwas_list_df = pd.DataFrame(columns = ["name", "path", "population", "n", "sampling", "prevalence", "mean", "sd", "label"])

gwas_list_df_eur = gwas_list_df.loc[gwas_list_df['population'] == 'EUR']

if 'gwas_list' in config:
  rule sumstat_prep_i:
    input:
      config['gwas_list'],
      config['config_file'],
      rules.get_dependencies.output
    output:
      "{outdir}/reference/gwas_sumstat/{gwas}/{gwas}-cleaned.gz"
    conda:
      "../envs/analysis.yaml"
    params:
      population= lambda w: gwas_list_df.loc[gwas_list_df['name'] == "{}".format(w.gwas), 'population'].iloc[0],
      path= lambda w: gwas_list_df.loc[gwas_list_df['name'] == "{}".format(w.gwas), 'path'].iloc[0]
    shell:
      """
      sumstat_cleaner_script=$(Rscript -e 'cat(system.file("scripts", "sumstat_cleaner.R", package = "GenoUtils"))')
      Rscript $sumstat_cleaner_script \
        --sumstats {params.path} \
        --ref_chr resources/data/ref/ref.chr \
        --population {params.population} \
        --output {outdir}/reference/gwas_sumstat/{wildcards.gwas}/{wildcards.gwas}-cleaned
      """

rule sumstat_prep:
  input: expand("{outdir}/reference/gwas_sumstat/{gwas}/{gwas}-cleaned.gz", gwas=gwas_list_df['name'], outdir=outdir)

##
# pT+clump (sparse, nested)
##

rule prep_pgs_ptclump_i:
  input:
    "{outdir}/reference/gwas_sumstat/{gwas}/{gwas}-cleaned.gz"
  output:
    "{outdir}/reference/pgs_score_files/ptclump/{gwas}/ref-{gwas}-EUR.scale"
  conda:
    "../envs/analysis.yaml"
  params:
    population= lambda w: gwas_list_df.loc[gwas_list_df['name'] == "{}".format(w.gwas), 'population'].iloc[0],
    testing=config["testing"]
  shell:
    "Rscript ../Scripts/pgs_methods/ptclump.R \
      --ref_plink_chr resources/data/ref/ref.chr \
      --ref_keep resources/data/ref/keep_files/{params.population}.keep \
      --sumstats {outdir}/reference/gwas_sumstat/{wildcards.gwas}/{wildcards.gwas}-cleaned.gz \
      --output {outdir}/reference/pgs_score_files/ptclump/{wildcards.gwas}/ref-{wildcards.gwas} \
      --pop_data resources/data/ref/ref.pop.txt \
      --test {params.testing}"

rule prep_pgs_ptclump:
  input: expand("{outdir}/reference/pgs_score_files/ptclump/{gwas}/ref-{gwas}-EUR.scale", gwas=gwas_list_df['name'], outdir=outdir)

##
# DBSLMM
##

rule prep_pgs_dbslmm_i:
  input:
    "{outdir}/reference/gwas_sumstat/{gwas}/{gwas}-cleaned.gz",
    rules.get_dependencies.output
  output:
    "{outdir}/reference/pgs_score_files/dbslmm/{gwas}/ref-{gwas}-EUR.scale"
  conda:
    "../envs/analysis.yaml"
  params:
    population= lambda w: gwas_list_df.loc[gwas_list_df['name'] == "{}".format(w.gwas), 'population'].iloc[0],
    sampling= lambda w: gwas_list_df.loc[gwas_list_df['name'] == "{}".format(w.gwas), 'sampling'].iloc[0],
    prevalence= lambda w: gwas_list_df.loc[gwas_list_df['name'] == "{}".format(w.gwas), 'prevalence'].iloc[0],
    testing=config["testing"]
  shell:
    "Rscript ../Scripts/pgs_methods/dbslmm.R \
      --ref_plink_chr resources/data/ref/ref.chr \
      --ref_keep resources/data/ref/keep_files/{params.population}.keep \
      --sumstats {outdir}/reference/gwas_sumstat/{wildcards.gwas}/{wildcards.gwas}-cleaned.gz \
      --ld_blocks resources/data/ld_blocks/{params.population} \
      --plink resources/software/plink/plink \
      --dbslmm resources/software/dbslmm/software \
      --munge_sumstats resources/software/ldsc/munge_sumstats.py \
      --ldsc resources/software/ldsc/ldsc.py \
      --ldsc_ref resources/data/ldsc_ref/eur_w_ld_chr \
      --hm3_snplist resources/data/hm3_snplist/w_hm3.snplist \
      --sample_prev {params.sampling} \
      --pop_prev {params.prevalence} \
      --output {outdir}/reference/pgs_score_files/dbslmm/{wildcards.gwas}/ref-{wildcards.gwas} \
      --pop_data resources/data/ref/ref.pop.txt \
      --test {params.testing}"

rule prep_pgs_dbslmm:
  input: expand("{outdir}/reference/pgs_score_files/dbslmm/{gwas}/ref-{gwas}-EUR.scale", gwas=gwas_list_df_eur['name'], outdir=outdir)

##
# PRScs
##

# Set default values
n_cores_prscs = config.get("ncores", 10)
mem_prscs = 80000

# Modify if the 'testing' condition is met
if config["testing"] != 'NA':
    mem_prscs = 40000
    n_cores_prscs = config.get("ncores", 5)

rule prep_pgs_prscs_i:
  resources:
    mem_mb=mem_prscs,
    cpus=n_cores_prscs,
    time_min=800
  input:
    "{outdir}/reference/gwas_sumstat/{gwas}/{gwas}-cleaned.gz",
    rules.get_dependencies.output,
    rules.download_prscs_software.output,
    rules.download_prscs_ref_1kg_eur.output
  output:
    "{outdir}/reference/pgs_score_files/prscs/{gwas}/ref-{gwas}-EUR.scale"
  conda:
    "../envs/analysis.yaml"
  params:
    testing=config["testing"]
  shell:
    "export MKL_NUM_THREADS=1; \
     export NUMEXPR_NUM_THREADS=1; \
     export OMP_NUM_THREADS=1; \
     Rscript ../Scripts/pgs_methods/prscs.R \
      --ref_plink_chr resources/data/ref/ref.chr \
      --sumstats {outdir}/reference/gwas_sumstat/{wildcards.gwas}/{wildcards.gwas}-cleaned.gz \
      --output {outdir}/reference/pgs_score_files/prscs/{wildcards.gwas}/ref-{wildcards.gwas} \
      --pop_data resources/data/ref/ref.pop.txt \
      --PRScs_path resources/software/prscs/PRScs.py \
      --PRScs_ref_path resources/data/prscs_ref/ldblk_1kg_eur \
      --n_cores {n_cores_prscs} \
      --phi_param 1e-6,1e-4,1e-2,1,auto \
      --test {params.testing}"

rule prep_pgs_prscs:
  input: expand("{outdir}/reference/pgs_score_files/prscs/{gwas}/ref-{gwas}-EUR.scale", gwas=gwas_list_df_eur['name'], outdir=outdir)

##
# SBayesR
##

if config["testing"] != 'NA':
  n_cores_sbayesr=min(1, multiprocessing.cpu_count())
  mem_sbayesr=10000
else:
  n_cores_sbayesr=min(10, multiprocessing.cpu_count())
  mem_sbayesr=80000

rule prep_pgs_sbayesr_i:
  resources:
    mem_mb=mem_sbayesr,
    cpus=n_cores_sbayesr
  input:
    "{outdir}/reference/gwas_sumstat/{gwas}/{gwas}-cleaned.gz",
    rules.get_dependencies.output,
    rules.download_gctb_ref.output,
    rules.download_gctb_software.output
  output:
    "{outdir}/reference/pgs_score_files/sbayesr/{gwas}/ref-{gwas}-EUR.scale"
  conda:
    "../envs/analysis.yaml"
  params:
    testing=config["testing"]
  shell:
    "Rscript ../Scripts/pgs_methods/sbayesr.R \
      --ref_plink_chr resources/data/ref/ref.chr \
      --sumstats {outdir}/reference/gwas_sumstat/{wildcards.gwas}/{wildcards.gwas}-cleaned.gz \
      --gctb resources/software/gctb/gctb_2.03beta_Linux/gctb \
      --ld_matrix_chr resources/data/gctb_ref/ukbEURu_hm3_shrunk_sparse/ukbEURu_hm3_v3_50k_chr \
      --robust T \
      --n_cores {n_cores_sbayesr} \
      --output {outdir}/reference/pgs_score_files/sbayesr/{wildcards.gwas}/ref-{wildcards.gwas} \
      --pop_data resources/data/ref/ref.pop.txt \
      --test {params.testing}"

rule prep_pgs_sbayesr:
  input: expand("{outdir}/reference/pgs_score_files/sbayesr/{gwas}/ref-{gwas}-EUR.scale", gwas=gwas_list_df_eur['name'], outdir=outdir)

##
# lassosum
##

if config["testing"] != 'NA':
  n_cores_lassosum=min(1, multiprocessing.cpu_count())
  mem_lassosum=10000
else:
  n_cores_lassosum=min(10, multiprocessing.cpu_count())
  mem_lassosum=80000

rule prep_pgs_lassosum_i:
  resources:
    mem_mb=mem_lassosum,
    cpus=n_cores_lassosum
  input:
    "{outdir}/reference/gwas_sumstat/{gwas}/{gwas}-cleaned.gz",
    rules.get_dependencies.output
  output:
    "{outdir}/reference/pgs_score_files/lassosum/{gwas}/ref-{gwas}-EUR.scale"
  conda:
    "../envs/analysis.yaml"
  params:
    population= lambda w: gwas_list_df.loc[gwas_list_df['name'] == "{}".format(w.gwas), 'population'].iloc[0],
    testing=config["testing"]
  shell:
    "Rscript ../Scripts/pgs_methods/lassosum.R \
     --ref_plink_chr resources/data/ref/ref.chr \
     --ref_keep resources/data/ref/keep_files/{params.population}.keep \
     --gwas_pop {params.population} \
     --sumstats {outdir}/reference/gwas_sumstat/{wildcards.gwas}/{wildcards.gwas}-cleaned.gz \
     --output {outdir}/reference/pgs_score_files/lassosum/{wildcards.gwas}/ref-{wildcards.gwas} \
     --n_cores {n_cores_lassosum} \
     --pop_data resources/data/ref/ref.pop.txt \
     --test {params.testing}"

rule prep_pgs_lassosum:
  input: expand("{outdir}/reference/pgs_score_files/lassosum/{gwas}/ref-{gwas}-EUR.scale", gwas=gwas_list_df['name'], outdir=outdir)

##
# LDpred2
##

if config["testing"] != 'NA':
  n_cores_ldpred2=min(5, multiprocessing.cpu_count())
  mem_ldpred2=40000
else:
  n_cores_ldpred2=min(10, multiprocessing.cpu_count())
  mem_ldpred2=80000

rule prep_pgs_ldpred2_i:
  resources:
    mem_mb=mem_ldpred2,
    cpus=n_cores_ldpred2,
    time_min=800
  input:
    rules.get_dependencies.output,
    "{outdir}/reference/gwas_sumstat/{gwas}/{gwas}-cleaned.gz",
    rules.download_ldpred2_ref.output
  output:
    "{outdir}/reference/pgs_score_files/ldpred2/{gwas}/ref-{gwas}-EUR.scale"
  conda:
    "../envs/analysis.yaml"
  params:
    testing=config["testing"]
  shell:
    "export OPENBLAS_NUM_THREADS=1; \
    Rscript ../Scripts/pgs_methods/ldpred2.R \
      --ref_plink_chr resources/data/ref/ref.chr \
      --ref_keep resources/data/ref/keep_files/EUR.keep \
      --ldpred2_ref_dir resources/data/ldpred2_ref \
      --sumstats {outdir}/reference/gwas_sumstat/{wildcards.gwas}/{wildcards.gwas}-cleaned.gz \
      --n_cores {n_cores_ldpred2} \
      --output {outdir}/reference/pgs_score_files/ldpred2/{wildcards.gwas}/ref-{wildcards.gwas} \
      --pop_data resources/data/ref/ref.pop.txt \
      --test {params.testing}"

rule prep_pgs_ldpred2:
  input: expand("{outdir}/reference/pgs_score_files/ldpred2/{gwas}/ref-{gwas}-EUR.scale", gwas=gwas_list_df_eur['name'], outdir=outdir)

##
# LDAK MegaPRS
##

if config["testing"] != 'NA':
  n_cores_megaprs=min(5, multiprocessing.cpu_count())
  mem_megaprs=40000
else:
  n_cores_megaprs=min(10, multiprocessing.cpu_count())
  mem_megaprs=80000

rule prep_pgs_megaprs_i:
  resources:
    mem_mb=mem_megaprs,
    cpus=n_cores_megaprs,
    time_min=800
  input:
    rules.get_dependencies.output,
    "{outdir}/reference/gwas_sumstat/{gwas}/{gwas}-cleaned.gz",
    rules.download_ldak_highld.output,
    rules.download_ldak.output,
    rules.download_ldak_bld.output
  output:
    "{outdir}/reference/pgs_score_files/megaprs/{gwas}/ref-{gwas}-EUR.scale"
  conda:
    "../envs/analysis.yaml"
  params:
    population= lambda w: gwas_list_df.loc[gwas_list_df['name'] == "{}".format(w.gwas), 'population'].iloc[0],
    testing=config["testing"]
  shell:
    "Rscript ../Scripts/pgs_methods/megaprs.R \
      --ref_plink_chr resources/data/ref/ref.chr \
      --ref_keep resources/data/ref/keep_files/{params.population}.keep \
      --sumstats {outdir}/reference/gwas_sumstat/{wildcards.gwas}/{wildcards.gwas}-cleaned.gz \
      --ldak resources/software/ldak/ldak5.1.linux \
      --ldak_map resources/data/ldak_map/genetic_map_b37 \
      --ldak_tag resources/data/ldak_bld \
      --ldak_highld resources/data/ldak_highld/highld.txt \
      --n_cores {n_cores_megaprs} \
      --output {outdir}/reference/pgs_score_files/megaprs/{wildcards.gwas}/ref-{wildcards.gwas} \
      --pop_data resources/data/ref/ref.pop.txt \
      --test {params.testing}"

rule prep_pgs_megaprs:
  input: expand("{outdir}/reference/pgs_score_files/megaprs/{gwas}/ref-{gwas}-EUR.scale", gwas=gwas_list_df['name'], outdir=outdir)

##
# Process externally created score files
##

if 'score_list' in config and config["score_list"] != 'NA':
  score_list_df = pd.read_table(config["score_list"], sep=r'\s+')
  score_list_catalogue_df = score_list_df[pd.isna(score_list_df['path'])]
  pgs_methods = config['pgs_methods']
  pgs_methods.append('external')
else:
  score_list_df = pd.DataFrame(columns = ["name", "path", "label"])
  score_list_catalogue_df = pd.DataFrame(columns = ["name", "path", "label"])
  pgs_methods = config['pgs_methods']

def check_score_path(w):
  # Check if the path value is not NA
  if not pd.isna(score_list_df.loc[score_list_df['name'] == w.gwas, 'path'].iloc[0]):
      return [score_list_df.loc[score_list_df['name'] == w.gwas, 'path'].iloc[0]]
  else:
      return []

def check_score_list():
  # Check if the path value is not NA
  if 'score_list' in config and config["score_list"] != 'NA':
      return [config['score_list']]
  else:
      return []

def score_path(w):
  # Check if the path value is not NA
  if not pd.isna(score_list_df.loc[score_list_df['name'] == w.gwas, 'path'].iloc[0]):
      return [score_list_df.loc[score_list_df['name'] == w.gwas, 'path'].iloc[0]]
  else:
      return [outdir + "/reference/pgs_score_files/raw_external/" + w.gwas + "_hmPOS_GRCh37.txt.gz"]

rule download_pgs_external:
  input:
    check_score_list(),
    config['config_file'],
    rules.get_dependencies.output
  output:
    touch("{outdir}/reference/target_checks/download_pgs_external.done")
  params:
    cat_score_ids= ' '.join(score_list_df['name'].astype(str)),
  conda:
    "../envs/analysis.yaml"
  shell:
    "mkdir -p {outdir}/reference/pgs_score_files/raw_external; \
    download_scorefiles -w -i {params.cat_score_ids} -o {outdir}/reference/pgs_score_files/raw_external -b GRCh37"

prep_pgs_external_input = list()
if not score_list_catalogue_df.empty:
  prep_pgs_external_input.append(rules.download_pgs_external.output)

rule prep_pgs_external_i:
  input:
    check_score_list(),
    config['config_file'],
    rules.get_dependencies.output,
    lambda w: check_score_path(w),
    prep_pgs_external_input
  output:
    touch("{outdir}/reference/target_checks/prep_pgs_external_i-{gwas}.done")
  params:
    score= lambda w: score_path(w),
    testing=config["testing"]
  conda:
    "../envs/analysis.yaml"
  shell:
    "Rscript ../Scripts/external_score_processor/external_score_processor.R \
      --ref_plink_chr resources/data/ref/ref.chr \
      --score {params.score} \
      --output {outdir}/reference/pgs_score_files/external/{wildcards.gwas}/ref-{wildcards.gwas} \
      --pop_data resources/data/ref/ref.pop.txt \
      --test {params.testing}"

rule prep_pgs_external:
  input: expand("{outdir}/reference/target_checks/prep_pgs_external_i-{gwas}.done", gwas=score_list_df['name'], outdir=outdir)

# Create a file listing target samples and population assignments
checkpoint score_reporter:
  input:
    expand("{outdir}/reference/target_checks/prep_pgs_external_i-{gwas}.done", gwas=score_list_df['name'], outdir=outdir)
  output:
    touch("{outdir}/reference/target_checks/score_reporter.done")
  conda:
    "../envs/analysis.yaml"
  params:
    config_file = config["config_file"]
  shell:
    "Rscript ../Scripts/pipeline_misc/score_reporter.R {params.config_file}"

##
# Use a rule to check requested PGS methods have been run for all GWAS
##

pgs_methods_input = list()

if 'ptclump' in pgs_methods:
  pgs_methods_input.append(rules.prep_pgs_ptclump.input)
if 'dbslmm' in pgs_methods:
  pgs_methods_input.append(rules.prep_pgs_dbslmm.input)
if 'prscs' in pgs_methods:
  pgs_methods_input.append(rules.prep_pgs_prscs.input)
if 'sbayesr' in pgs_methods:
  pgs_methods_input.append(rules.prep_pgs_sbayesr.input)
if 'lassosum' in pgs_methods:
  pgs_methods_input.append(rules.prep_pgs_lassosum.input)
if 'ldpred2' in pgs_methods:
  pgs_methods_input.append(rules.prep_pgs_ldpred2.input)
if 'megaprs' in pgs_methods:
  pgs_methods_input.append(rules.prep_pgs_megaprs.input)
if 'external' in pgs_methods:
  pgs_methods_input.append(rules.prep_pgs_external.input)

rule prep_pgs:
  input:
    pgs_methods_input
