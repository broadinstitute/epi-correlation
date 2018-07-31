version 1.0

struct PairInfo {
  File bamA
  File bamB
  Int? extensionFactor
}

struct Output {
  File bamA
  File bamB
  Float corr
}

workflow Correlation {

  input {
    Array[PairInfo] inputs
    String dockerImage
  }

  scatter (pInfo in inputs) {
    call correlateBams {
      input:
        in = pInfo,
        dockerImage = dockerImage,
    }
  }

  output {
    Array[Output] correlations = correlateBams.out
  }
}

task correlateBams {
  input {
    PairInfo in
    String dockerImage
  }

  command {
    ./runEntirePipeline.sh \
      ${if in.extensionFactor then "-l ${in.extensionFactor}" else "-p"} \
      -a ${in.bamA} \
      -b ${in.bamB}
  }

  output {
    Output out = {
      "bamA": "${in.bamA}",
      "bamB": "${in.bamB}",
      "corr": "${stdout()}",
    }
  }

  runtime {
    docker: dockerImage
    disks: "local-disk 25 HDD"
  }
}