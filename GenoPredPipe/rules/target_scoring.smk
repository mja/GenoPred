####
# PC scoring
####

rule target_pc:
  input:
    "resources/data/target_checks/{name}/ancestry_reporter.done",
    rules.run_pop_pc_scoring.input,
    "../Scripts/scaled_ancestry_scorer/scaled_ancestry_scorer.R"
  output:
    touch("resources/data/target_checks/{name}/target_pc_{population}.done")
  conda:
    "../envs/GenoPredPipe.yaml"
  params:
    output= lambda w: target_list_df.loc[target_list_df['name'] == "{}".format(w.name), 'output'].iloc[0]
  shell:
    "Rscript ../Scripts/Scaled_polygenic_scorer/Scaled_polygenic_scorer_plink2.R \
      --target_plink_chr {params.output}/{wildcards.name}/{wildcards.name}.ref.chr \
      --target_keep {params.output}/{wildcards.name}/ancestry/ancestry_all/{wildcards.name}.Ancestry.model_pred.{wildcards.population}.keep \
      --ref_freq_chr resources/data/ref/freq_files/{wildcards.population}/ref.{wildcards.population}.chr \
      --ref_score resources/data/ref/pc_score_files/{wildcards.population}/ref.{wildcards.population}.eigenvec.var \
      --ref_scale resources/data/ref/pc_score_files/{wildcards.population}/ref.{wildcards.population}.scale \
      --plink2 plink2 \
      --output {params.output}/{wildcards.name}/projected_pc/{wildcards.population}/{wildcards.name}"
      
rule run_target_pc_all_pop:
  input: 
    lambda w: expand("resources/data/target_checks/{name}/target_pc_{population}.done", name=w.name, population=ancestry_munge("{}".format(w.name)))
  output:
    touch("resources/data/target_checks/{name}/run_target_pc_all_pop.done")

rule run_target_pc_all:
  input: 
    expand("resources/data/target_checks/{name}/run_target_pc_all_pop.done", name=target_list_df['name'])

####
# Polygenic scoring
####

rule target_prs:
  input:
    "resources/data/target_checks/{name}/ancestry_reporter.done",
    "resources/data/ref/prs_score_files/{method}/{gwas}/ref.{gwas}.EUR.scale",
    "../Scripts/Scaled_polygenic_scorer/Scaled_polygenic_scorer_plink2.R",
    "../Scripts/functions/misc.R"
  output:
    touch("resources/data/target_checks/{name}/target_prs_{method}_{population}_{gwas}.done")
  conda:
    "../envs/GenoPredPipe.yaml"
  params:
    output= lambda w: target_list_df.loc[target_list_df['name'] == "{}".format(w.name), 'output'].iloc[0]
  shell:
    "Rscript ../Scripts/Scaled_polygenic_scorer/Scaled_polygenic_scorer_plink2.R \
      --target_plink_chr {params.output}/{wildcards.name}/{wildcards.name}.ref.chr \
      --target_keep {params.output}/{wildcards.name}/ancestry/ancestry_all/{wildcards.name}.Ancestry.model_pred.{wildcards.population}.keep \
      --ref_score resources/data/ref/prs_score_files/{wildcards.method}/{wildcards.gwas}/ref.{wildcards.gwas}.score.gz \
      --ref_scale resources/data/ref/prs_score_files/{wildcards.method}/{wildcards.gwas}/ref.{wildcards.gwas}.{wildcards.population}.scale \
      --ref_freq_chr resources/data/ref/freq_files/{wildcards.population}/ref.{wildcards.population}.chr \
      --plink2 plink2 \
      --pheno_name {wildcards.gwas} \
      --output {params.output}/{wildcards.name}/prs/{wildcards.population}/{wildcards.method}/{wildcards.gwas}/{wildcards.name}.{wildcards.gwas}.{wildcards.population}"

rule run_target_prs_all_gwas:
  input:
    config["gwas_list"],
    lambda w: expand("resources/data/target_checks/{name}/target_prs_{method}_{population}_{gwas}.done", name=w.name, gwas=gwas_list_df['name'], population=w.population, method=w.method)
  output:
    touch("resources/data/target_checks/{name}/run_target_prs_{method}_all_gwas_{population}.done")

rule run_target_prs_all_pop:
  input: 
    lambda w: expand("resources/data/target_checks/{name}/run_target_prs_{method}_all_gwas_{population}.done", name=w.name, population=ancestry_munge("{}".format(w.name)), method=w.method)
  output:
    touch("resources/data/target_checks/{name}/run_target_prs_{method}_all_pop.done")

rule run_target_prs_all_name:
  input: 
    lambda w: expand("resources/data/target_checks/{name}/run_target_prs_{method}_all_pop.done", name=target_list_df['name'], method=w.method)
  output:
    touch("resources/data/target_checks/run_target_prs_{method}_all_name.done")

rule run_target_prs_all_method:
  input: 
    expand("resources/data/target_checks/run_target_prs_{method}_all_name.done", method=config["pgs_methods"])
  output:
    touch("resources/data/target_checks/run_target_prs_all_method.done")

##
# Externally created score files
##

rule target_prs_external:
  resources: 
    mem_mb=30000
  input:
    lambda w: score_list_df.loc[score_list_df['name'] == "{}".format(w.gwas), 'path'].iloc[0],
    "resources/data/target_checks/{name}/ancestry_reporter.done",
    "resources/data/ref/prs_score_files/external/{gwas}/ref.{gwas}.EUR.scale",
    "../Scripts/Scaled_polygenic_scorer/Scaled_polygenic_scorer_plink2.R"
  output:
    touch("resources/data/target_checks/{name}/target_prs_external_{population}_{gwas}.done")
  conda:
    "../envs/GenoPredPipe.yaml"
  params:
    score= lambda w: score_list_df.loc[score_list_df['name'] == "{}".format(w.gwas), 'path'].iloc[0],
    output= lambda w: target_list_df.loc[target_list_df['name'] == "{}".format(w.name), 'output'].iloc[0]
  shell:
    "Rscript ../Scripts/Scaled_polygenic_scorer/Scaled_polygenic_scorer_plink2.R \
      --target_plink_chr {params.output}/{wildcards.name}/{wildcards.name}.ref.chr \
      --target_keep {params.output}/{wildcards.name}/ancestry/ancestry_all/{wildcards.name}.Ancestry.model_pred.{wildcards.population}.keep \
      --ref_score {params.score} \
      --ref_scale resources/data/ref/prs_score_files/external/{wildcards.gwas}/ref.{wildcards.gwas}.{wildcards.population}.scale \
      --ref_freq_chr resources/data/ref/freq_files/{wildcards.population}/ref.{wildcards.population}.chr \
      --plink2 plink2 \
      --pheno_name {wildcards.gwas} \
      --output {params.output}/{wildcards.name}/prs/{wildcards.population}/external/{wildcards.gwas}/{wildcards.name}.{wildcards.gwas}.{wildcards.population}"
     
rule run_target_prs_external_all_gwas:
  input: 
    config["score_list"],
    lambda w: expand("resources/data/target_checks/{name}/target_prs_external_{population}_{gwas}.done", name=w.name, gwas=score_list_df['name'], population=w.population)
  output:
    touch("resources/data/target_checks/{name}/run_target_prs_external_all_gwas_{population}.done")

rule run_target_prs_external_all_pop:
  input: 
    lambda w: expand("resources/data/target_checks/{name}/run_target_prs_external_all_gwas_{population}.done", name=w.name, population=ancestry_munge("{}".format(w.name)))
  output:
    touch("resources/data/target_checks/{name}/run_target_prs_external_all_pop.done")

rule run_target_prs_external_all_name:
  input: 
    expand("resources/data/target_checks/{name}/run_target_prs_external_all_pop.done", name=target_list_df['name'])
  output:
    touch("resources/data/target_checks/prs_external.done")

##
# Calculate PRS using all methods
##

rule target_prs_all:
  input:
    lambda w: expand("resources/data/target_checks/{name}/run_target_prs_pt_clump_all_pop.done", name=w.name),
    lambda w: expand("resources/data/target_checks/{name}/run_target_prs_dbslmm_all_pop.done", name=w.name),
    lambda w: expand("resources/data/target_checks/{name}/run_target_prs_prscs_all_pop.done", name=w.name),
    lambda w: expand("resources/data/target_checks/{name}/run_target_prs_sbayesr_all_pop.done", name=w.name),
    lambda w: expand("resources/data/target_checks/{name}/run_target_prs_lassosum_all_pop.done", name=w.name),
    lambda w: expand("resources/data/target_checks/{name}/run_target_prs_ldpred2_all_pop.done", name=w.name),
    lambda w: expand("resources/data/target_checks/{name}/run_target_prs_megaprs_all_pop.done", name=w.name),
    lambda w: expand("resources/data/target_checks/{name}/run_target_prs_external_all_pop.done", name=w.name)
  output:
    touch('resources/data/target_checks/{name}/target_prs_all.done')

rule run_target_prs_all:
  input: expand('resources/data/target_checks/{name}/target_prs_all.done', name=target_list_df['name'])
