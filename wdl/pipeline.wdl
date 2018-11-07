version 1.0

struct InputBam {
  String name
  File bam
  File? bai
}

struct InputPair {
  InputBam inA
  InputBam inB
  Boolean? isMint
  String? genome
}

struct OutputPair {
  String nameA
  String nameB
  Float corr
}

workflow Correlation {
  input {
    # List of pairs to be compared
    Array[InputPair] inputPairs

    # Optional list of known correlations,
    # to be added to the final report
    Array[OutputPair] existingOutputs = []

    # GCS folder where to store the output data
    String outputsDir

    # GCS file in which to store the output JSON
    String outputsJson

    # Docker image for the correlation pipeline
    String dockerImage
  }

  scatter (pair in inputPairs) {
    call correlatePair {
      input:
        inA = pair.inA,
        inB = pair.inB,
        isMint = pair.isMint,
        genome = pair.genome,
        dockerImage = dockerImage,
    }
  }

  call reportOutputs {
    input:
      existingOutputs = existingOutputs,
      newOutputs = correlatePair.out,
      outputsDir = outputsDir,
      outputsJson = outputsJson,
      dockerImage = dockerImage,
  }
}

task correlatePair {
  input {
    InputBam inA
    InputBam inB
    Boolean isMint = false
    String genome = "hg19"

    String dockerImage
  }

  Int bamASize = ceil(size(inA.bam, 'GB'))
  Int bamBSize = ceil(size(inB.bam, 'GB'))
  Int javaMemory = if bamASize > bamBSize then bamASize else bamBSize
  Int memory = 2 * javaMemory + 1

  String baiArgA = if defined(inA.bai) then "--bai-a '~{inA.bai}'" else ''
  String baiArgB = if defined(inB.bai) then "--bai-b '~{inB.bai}'" else ''
  String mintArg = if isMint then "--mint" else ''

  command {
    /scripts/runEntirePipeline.sh \
      --custom-memory ~{javaMemory}g \
      ~{mintArg} \
      --bam-a '~{inA.bam}' \
      --bam-b '~{inB.bam}' \
      ~{baiArgA} \
      ~{baiArgB} \
      --genome ~{genome} \
      --debug
  }

  output {
    OutputPair out = object {
      nameA: inA.name,
      nameB: inB.name,
      corr: read_float('output/cor_out.txt'),
    }
  }

  runtime {
    docker: dockerImage
    disks: 'local-disk 25 HDD'
    memory: memory + 'G'
    cpu: 4
  }
}

task reportOutputs {
  input {
    Array[OutputPair] existingOutputs
    Array[OutputPair] newOutputs
    String outputsDir
    String outputsJson

    String dockerImage
  }

  # Write existing outputs & new outputs to a JSON file
  File reportInputs = write_objects(flatten([
    existingOutputs,
    newOutputs,
  ]))

  # Write only new outputs to a JSON file
  File newOutputsJson = write_json(object {
    outputs: newOutputs,
  })

  # Generates report using all output,
  # writes JSON file of only new outputs to specified location
  command {
    set -e

    /scripts/generateReports.sh '~{reportInputs}'

    gsutil cp report.* '~{outputsDir}/'
    gsutil cp '~{newOutputsJson}' '~{outputsJson}'
  }

  runtime {
    docker: dockerImage
    disks: 'local-disk 25 HDD'
    memory: '1G'
    cpu: 1
  }
}
