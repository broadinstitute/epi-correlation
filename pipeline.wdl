version 1.0

struct PairInfo {
  File bamA
  File bamB
  File baiA
  File baiB
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
    /scripts/runEntirePipeline.sh -d -n \
      ${if defined(in.extensionFactor) then "-l ${in.extensionFactor}" else "-p"} \
      -a ${in.bamA} \
      -b ${in.bamB} \
      -i ${in.baiA} \
      -j ${in.baiB}
  }

  output {
    Output out = object {
      bamA: in.bamA,
      bamB: in.bamB,
      corr: read_float("output/cor_out.txt"),
    }
  }

  runtime {
    docker: dockerImage
    cpu: 2
    disks: "local-disk 25 HDD"
  }
}
