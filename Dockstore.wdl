version 1.0

#
# WDL workflows for running population genetics simulations using cosi2
#

#
# TODO:
#
#   include metadata including selection start/stop/pop in workflow output as table
#   and muation age
#
#   figure out how to enable result caching without 
#

task cosi2_run_one_sim_block {
  meta {
    description: "Run one block of cosi2 simulations for one demographic model."
    email: "ilya_shl@alum.mit.edu"
  }

  parameter_meta {
    # Inputs
    paramFile: "parts cosi2 parameter file (concatenated to form the parameter file)"
    recombFile: "recombination map"
    simBlockId: "an ID of this simulation block (e.g. block number in a list of blocks)."
    nSimsInBlock: "number of simulations in this block"

    # Outputs
    tpeds: ".tar.gz file containing simulated samples for each population"
  }

  input {
    File         paramFile
    File         recombFile
    String       simBlockId
    Int          nSimsInBlock = 1
    Int          maxAttempts = 10000000
    Int          randomSeed = 0
    String       cosi2_docker = "quay.io/ilya_broad/dockstore-tool-cosi2@sha256:d00da9c93fba843ae9e516230d03a7a8263295773da836c166c93d1532920441"
  }

  command <<<
    grep -v "recomb_file" "~{paramFile}" > ~{simBlockId}.fixed.par
    echo "recomb_file ~{recombFile}" >> ~{simBlockId}.fixed.par

    if [ "~{randomSeed}" -eq "0" ]; then
       cat /dev/urandom | od -vAn -N4 -tu4 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | sed 's/.$//' > cosi2.randseed
    else
       echo "~{randomSeed}" > cosi2.randseed
    fi
    
    env COSI_NEWSIM=1 COSI_MAXATTEMPTS=~{maxAttempts} COSI_SAVE_TRAJ="~{simBlockId}.traj" COSI_SAVE_SWEEP_INFO="sweepinfo.tsv" coalescent -p ~{simBlockId}.fixed.par -v -g -r $(cat "cosi2.randseed") -n ~{nSimsInBlock} --genmapRandomRegions --drop-singletons .25 --tped "~{simBlockId}" 
    #cat ~{simBlockId}.fixed.par | grep sweep_mult_standing | awk '{print $4;}' > sel_mut_born_pop.txt
    #cat ~{simBlockId}.fixed.par | grep sweep_mult_standing | awk '{print $5;}' > sel_mut_born_gen.txt
    #cat ~{simBlockId}.fixed.par | grep sweep_mult_standing | awk '{print $6;}' > sel_coeff.txt
    #cat ~{simBlockId}.fixed.par | grep sweep_mult_standing | awk '{print $9;}' > sel_beg_gen.txt
    echo -e 'simNum\tselPop\tselGen\tselBegPop\tselBegGen\tselCoeff\tselFreq' > sweepinfo.full.tsv
    cat sweepinfo.tsv >> sweepinfo.full.tsv

    tar cvfz "~{simBlockId}.tpeds.tar.gz" *.tped
  >>>

  output {
    File        tpeds = "${simBlockId}.tpeds.tar.gz"
    Int         randomSeedUsed = read_int("cosi2.randseed")
    Object      sweepInfo = read_object("sweepinfo.full.tsv")

#    String      cosi2_docker_used = ""
  }
  runtime {
#    docker: "quay.io/ilya_broad/cms-dev:2.0.1-15-gd48e1db-is-cms2-new"
    docker: cosi2_docker
    memory: "3 GB"
    cpu: 2
    dx_instance_type: "mem1_ssd1_v2_x4"
    volatile: randomSeed==0
  }
}


workflow run_sims_cosi2 {
    meta {
      description: "Run a set of cosi2 simulations for one or more demographic models."
      author: "Ilya Shlyakhter"
      email: "ilya_shl@alum.mit.edu"
    }

    parameter_meta {
      paramFiles: "cosi2 parameter files specifying the demographic model (paramFileCommon is prepended to each)"
      recombFile: "Recombination map from which map of each simulated region is sampled"
      nreps: "Number of replicates for _each_ demographic model."
    }

    input {
      Array[File] paramFiles
      File recombFile
      Int nreps = 1
      Int nSimsPerBlock = 1
      String       cosi2_docker = "quay.io/ilya_broad/dockstore-tool-cosi2@sha256:d00da9c93fba843ae9e516230d03a7a8263295773da836c166c93d1532920441"
    }
    Int nBlocks = nreps / nSimsPerBlock
    #Array[String] paramFileCommonLines = read_lines(paramFileCommonLines)

    scatter(paramFile in paramFiles) {
        scatter(blockNum in range(nBlocks)) {
            call cosi2_run_one_sim_block {
                input:
                   paramFile = paramFile,
	           recombFile=recombFile,
	           simBlockId=basename(paramFile, ".par")+"_"+blockNum,
	           nSimsInBlock=nSimsPerBlock,
	           cosi2_docker=cosi2_docker
            }
        }
    }

    output {
      Array[File] tpeds = flatten(cosi2_run_one_sim_block.tpeds)
      Array[Int] randomSeedUsed = flatten(cosi2_run_one_sim_block.randomSeedUsed)
      Array[Object] sweepInfo = flatten(cosi2_run_one_sim_block.sweepInfo)
    }
}
