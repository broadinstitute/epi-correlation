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

  Int bamASize = ceil(size(in.bamA, 'GB'))
  Int bamBSize = ceil(size(in.bamB, 'GB'))
  Int memory = 2 * (if bamASize > bamBSize then bamASize else bamBSize) + 1

  command {
    /scripts/runEntirePipeline.sh -d -n -m ${(memory - 1)/2}g \
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
    cpu: 4
    memory: memory + "G"
    disks: "local-disk 25 HDD"
  }
}
