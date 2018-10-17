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
    String outputDir

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

  Array[OutputPair] outputPairs = flatten([
    correlatePair.out,
    existingOutputs,
  ])

  call generateReports {
    input:
      outputPairs = outputPairs,
      outputDir = outputDir,
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

task generateReports {
  input {
    Array[OutputPair] outputPairs
    String outputDir

    String dockerImage
  }

  File reportInputs = write_objects(outputPairs)

  command {
    /scripts/generateReports.sh '~{reportInputs}'
  }

  runtime {
    docker: dockerImage
    disks: 'local-disk 25 HDD'
    memory: '1G'
    cpu: 1
  }
}
