#!/usr/bin/env nextflow

params.results_dir= "$projectDir/results"

process RUN_IQTREE {
  label 'fast'

  publishDir "${params.results_dir}/${ds}/iqtree/", mode: 'copy'
  
  input:
    val(ds)
  output:
    tuple val(ds), path("dodo.bionj")
    path("iqtree-${ds}.csv")
    path("dodo.iqtree")
    path("dodo.log")
    path("dodo.treefile")
  """
  iqtree2 -s ${projectDir}/data/DS${ds}.nex -m GTR+FO --prefix dodo -T AUTO
  LNL=\$(grep "BEST SCORE" dodo.log | awk 'BEGIN{FS=" : "}{print \$2}')
  echo "iqtree,${ds},\$LNL" > iqtree-${ds}.csv
  """
}

process RUN_RAXML {
  label 'fast'

  publishDir "${params.results_dir}/${ds}/raxml/", mode: 'copy'
  
  input:
    val(ds)
  output:
    path("raxml-${ds}.csv")
    path("dodo.raxml.log")
    path("dodo.raxml.bestTree")
    path("dodo.raxml.bestModel")
  """
  nexus_to_fasta.py ${projectDir}/data/DS${ds}.nex > DS.fasta
  raxml-ng --model GTR --msa DS.fasta --prefix dodo
  LNL=\$(grep "Final LogLikelihood:" dodo.raxml.log | awk 'BEGIN{FS=": "}{print \$2}')
  echo "raxml,${ds},\$LNL" > raxml-${ds}.csv
  """
}

process RUN_DODONAPHY_HMAP {
  publishDir "${params.results_dir}/hmap/${ds}/", mode: 'copy'

  input:
    tuple val(ds), val(start)
  output:
    tuple val(ds), path("hmap/nj/None/lr2_tau5/mape.t")
    path("dodonaphy-${ds}.csv")
    path("hmap/nj/None/lr2_tau5/samples.t")
    path("hmap/nj/None/lr2_tau5/hmap.log")
    path("hmap/nj/None/lr2_tau5/posterior.txt")
    path("dodo.log")
    path("dodo.txt")
  """
  { time \
    dodo --infer hmap \
    --connect nj \
    --model GTR \
    --embed up \
    --path_dna ${projectDir}/data/DS${ds}.nex \
    --prior None \
    --epochs 2000 \
    --start ${start} \
    --dim 3 \
    --curv -100 \
    --learn 0.01 \
    --temp 0.00001 \
    > dodo.txt ; } 2> dodo.log

  LNL=\$(grep "Best log likelihood" hmap/nj/None/lr2_tau5/hmap.log | awk 'BEGIN{FS=": "}{print \$2}')
  echo "dodonaphy,${ds},\$LNL" > dodonaphy-${ds}.csv
  """
}

process RUN_DODONAPHY_VI {
  publishDir "${params.results_dir}/vi/${ds}/", mode: 'copy'

  input:
    tuple val(ds), val(start)
  output:
    path("samples.csv")
    path("samples.trees")
    path("dodo.log")
    path("dodo.txt")
  """
  { time \
    dodo --infer vi \
    --connect nj \
    --model JC69 \
    --embed up \
    --path_dna ${projectDir}/data/DS${ds}.nex \
    --prior gammadir \
    --epochs 2000 \
    --draws 10000 \
    --start ${start} \
    --dim 3 \
    --curv -100 \
    --learn 0.01 \
    --temp 0.00001 \
    --importance 1 --boosts 1 \
    > dodo.txt ; } 2> dodo.log
  """
}

process RUN_DODONAPHY_PLUS {
  label 'fast'

  publishDir "${params.results_dir}/hmap/${ds}/dodoplus/", mode: 'copy'
  
  input:
    tuple val(ds), path(treefile)
  output:
    path("dodonaphyplus-${ds}.csv")
    path("dodoplus.iqtree")
    path("dodoplus.log")
    path("dodoplus.treefile")
  """
  grep tree ${treefile} | awk 'BEGIN{FS="] "} {print \$3}' > mape.nwk
  iqtree2 -s ${projectDir}/data/DS${ds}.nex -te mape.nwk -m GTR+FO --prefix dodoplus -T AUTO
  LNL=\$(grep "BEST SCORE" dodoplus.log | awk 'BEGIN{FS=" : "}{print \$2}')
  echo "dodonaphyplus,${ds},\$LNL" > dodonaphyplus-${ds}.csv
  """
}

process RUN_IQTREE_BIONJ {
  label 'fast'

  publishDir "${params.results_dir}/hmap/${ds}/bionj/", mode: 'copy'
  
  input:
    tuple val(ds), path(treefile)
  output:
    path("bionj-${ds}.csv")
    path("bionj.iqtree")
    path("bionj.log")
    path("bionj.treefile")
  """
  iqtree2 -s ${projectDir}/data/DS${ds}.nex -te ${treefile} -m GTR+FO --prefix bionj -T AUTO
  LNL=\$(grep "BEST SCORE" bionj.log | awk 'BEGIN{FS=" : "}{print \$2}')
  echo "bionj,${ds},\$LNL" > bionj-${ds}.csv
  """
}

process COMBIME_CSV {
  label 'ultrafast'

  publishDir "${params.results_dir}/hmap/", mode: 'copy'

  input:
  path files
  output:
  path("results.csv")

  """
  echo "program,dataset,lnl" > results.csv
  cat *[0-9].csv >> results.csv
  """
}

workflow{
  ds = Channel.of(1..8)
  RUN_IQTREE(ds)
  RUN_RAXML(ds)
  RUN_DODONAPHY_HMAP(RUN_IQTREE.out[0])
  RUN_DODONAPHY_PLUS(RUN_DODONAPHY_HMAP.out[0])
  RUN_IQTREE_BIONJ(RUN_IQTREE.out[0])

  ch_files = Channel.empty()
  ch_files = ch_files.mix(
          RUN_IQTREE.out[1].collect(),
          RUN_RAXML.out[0].collect(),
          RUN_DODONAPHY_HMAP.out[1].collect(),
          RUN_DODONAPHY_PLUS.out[0].collect(),
          RUN_IQTREE_BIONJ.out[0].collect())
  COMBIME_CSV(ch_files.collect())
  
  RUN_DODONAPHY_VI(RUN_IQTREE.out[0])
}