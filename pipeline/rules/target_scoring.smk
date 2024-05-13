# Create a function summarising which populations are present in target
def ancestry_munge(x):
    checkpoints.ancestry_reporter.get(name=x).output[0]
    checkpoint_output = outdir + "/" + x + "/ancestry/ancestry_report.txt"
    ancestry_report_df = pd.read_table(checkpoint_output, sep=' ')
    return ancestry_report_df['population'].tolist()

# Create a function summarising which score files matched sufficiently with reference
def score_munge():
    checkpoints.score_reporter.get().output[0]
    checkpoint_output = outdir + "/reference/pgs_score_files/external/score_report.txt"

    if os.path.exists(checkpoint_output):
      score_report_df = pd.read_table(checkpoint_output, sep=' ')
      score_report_df = score_report_df[(score_report_df['pass'].isin(['T', 'TRUE', True]))]
    else:
      score_report_df = pd.DataFrame(columns=['name', 'pass'])

    return score_report_df['name'].tolist()

# Define which pgs_methods are can be applied to any GWAS population
pgs_methods_noneur = ['ptclump','lassosum','megaprs','prscs','dbslmm']

# Create a function listing all required PGS for a given target/s
def list_target_scores(names, population=None):
    # Initialize the list to store all target scores
    all_target_scores = []

    # Process each name in the provided list of names
    for name in names:
        # Determine the populations to process
        if population:
            populations = [population]
        else:
            populations = ancestry_munge(x=name)  # Assuming this function returns a list of populations

        scores = score_munge()  # Fetch score data

        target_scores = []
        # Loop through methods and their corresponding GWAS names
        for method in pgs_methods:
            gwas_names = gwas_list_df['name'] if method in pgs_methods_noneur else gwas_list_df_eur['name']
            for population in populations:
                for gwas in gwas_names:
                    target_scores.append(f"{outdir}/{{name}}/pgs/{{population}}/{method}/{gwas}/{{name}}-{gwas}-{{population}}.profiles")

        # Add external scores for each population
        for score in scores:
            for population in populations:
                target_scores.append(f"{outdir}/{{name}}/pgs/{{population}}/external/{score}/{{name}}-{score}-{{population}}.profiles")

        # Append the scores for this name to the main list
        all_target_scores.extend(target_scores)

    return all_target_scores

####
# Projected PCs
####

rule pc_projection_i:
  input:
    f"{outdir}/reference/target_checks/{{name}}/ancestry_reporter.done",
    f"{resdir}/data/ref/pc_score_files/{{population}}/ref-{{population}}-pcs.EUR.scale"
  output:
    touch(f"{outdir}/reference/target_checks/{{name}}/pc_projection-{{population}}.done")
  benchmark:
    f"{outdir}/reference/benchmarks/pc_projection_i-{{name}}-{{population}}.txt"
  log:
    f"{outdir}/reference/logs/pc_projection_i-{{name}}-{{population}}.log"
  conda:
    "../envs/analysis.yaml"
  shell:
    "Rscript ../Scripts/target_scoring/target_scoring.R \
      --target_plink_chr {outdir}/{wildcards.name}/geno/{wildcards.name}.ref.chr \
      --target_keep {outdir}/{wildcards.name}/ancestry/keep_files/model_based/{wildcards.population}.keep \
      --ref_freq_chr {refdir}/freq_files/{wildcards.population}/ref.{wildcards.population}.chr \
      --ref_score {resdir}/data/ref/pc_score_files/{wildcards.population}/ref-{wildcards.population}-pcs.eigenvec.var.gz \
      --ref_scale {resdir}/data/ref/pc_score_files/{wildcards.population}/ref-{wildcards.population}-pcs.{wildcards.population}.scale \
      --plink2 plink2 \
      --output {outdir}/{wildcards.name}/pcs/projected/{wildcards.population}/{wildcards.name}-{wildcards.population} > {log} 2>&1"

rule pc_projection_all:
  input:
    lambda w: expand(f"{outdir}/reference/target_checks/{{name}}/pc_projection-{{population}}.done", name=w.name, population=ancestry_munge("{}".format(w.name)))
  output:
    touch(f"{outdir}/reference/target_checks/{{name}}/pc_projection.done")

rule pc_projection:
  input:
    expand(f"{outdir}/reference/target_checks/{{name}}/pc_projection.done", name=target_list_df['name'])

####
# Polygenic scoring
####

if config["testing"] != 'NA':
  n_cores_target_scoring = config.get("ncores", 1)
else:
  n_cores_target_scoring = config.get("ncores", 10)

rule target_pgs_i:
  resources:
    mem_mb=8000,
    time_min=800
  threads: n_cores_target_scoring
  input:
    f"{outdir}/reference/target_checks/{{name}}/ancestry_reporter.done",
    rules.prep_pgs.input
  output:
    touch(f"{outdir}/reference/target_checks/{{name}}/target_pgs-{{population}}.done")
  benchmark:
    f"{outdir}/reference/benchmarks/target_pgs_i-{{name}}-{{population}}.txt"
  log:
    f"{outdir}/reference/logs/target_pgs_i-{{name}}-{{population}}.log"
  conda:
    "../envs/analysis.yaml"
  params:
    testing=config["testing"],
    config_file = config["config_file"]
  shell:
    "rm -r -f {outdir}/{wildcards.name}/pgs/{wildcards.population} && \
     Rscript ../Scripts/target_scoring/target_scoring_pipeline.R \
      --config {params.config_file} \
      --name {wildcards.name} \
      --population {wildcards.population} \
      --plink2 plink2 \
      --test {params.testing} \
      --n_cores {threads} > {log} 2>&1"

rule target_pgs_all:
  input:
    lambda w: expand(f"{outdir}/reference/target_checks/{{name}}/target_pgs-{{population}}.done", name=w.name, population = ancestry_munge(w.name))
  output:
    touch(f"{outdir}/reference/target_checks/{{name}}/target_pgs.done")

rule target_pgs:
  input:
    expand(f"{outdir}/reference/target_checks/{{name}}/target_pgs.done", name=target_list_df['name'])

