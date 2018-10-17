version 1.0

struct InputBam {
  String name
  File bam
  File? bai
}

struct InputPair {
  InputBam inA
  InputBam inB
  Int? extensionFactor
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
        extensionFactor = pair.extensionFactor,
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
    Int? extensionFactor

    String dockerImage
  }

  Int bamASize = ceil(size(inA.bam, 'GB'))
  Int bamBSize = ceil(size(inB.bam, 'GB'))
  Int javaMemory = if bamASize > bamBSize then bamASize else bamBSize
  Int memory = 2 * javaMemory + 1

  String baiArgA = if defined(inA.bai) then "-i '~{inA.bai}'" else ''
  String baiArgB = if defined(inB.bai) then "-j '~{inB.bai}'" else ''
  String extensionArg = if defined(extensionFactor) then '-l ~{extensionFactor}' else '' # TODO investigate why it fails with -p

  command {
    /scripts/runEntirePipeline.sh \
      -m ~{javaMemory}g \
      -a '~{inA.bam}' \
      -b '~{inB.bam}' \
      ~{baiArgA} \
      ~{baiArgB} \
      ~{extensionArg} \
      -d
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

  File reportInputs = write_objects(flatten([
    existingOutputs,
    newOutputs,
  ]))

  File newOutputsJson = write_json(object {
    outputs: newOutputs,
  })

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
