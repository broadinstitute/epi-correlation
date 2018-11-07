# Histone Modification ChIP Similarity Metric: Correlation
This package provides a method of determining similarity between two Histone Modification ChIP-seq aligned bam files.

# Using This Docker
## Installing
Download the repository to a local folder; use docker to build the container. Run the following command from the same directory as the Dockerfile:
```
docker build -t correlation .
```

## Testing
The docker automatically tests itself upon compilation. You should see the following output somewhere in the docker output:
```
Pipeline Testing Results:
File A vs File A:
1     PASS

File A vs File B:
-0.652163     PASS
```

If the docker failed to compile & one or more of these say FAIL, something went wrong and may require a bug report.

## Usage
`-h` Output:
```
        Please visit us on github for deeper explanations.
        [(-p|--paired)|(-l|--avg-read-length) <0-200>] : BAM file type; paired or single. If single, define the average read length.
        [-m|--mint] : Define the data as MINT data.
        [--genome <hg19/grch38>] : Define alignment genome.
        [--single-threaded] : Run in single threaded mode.
        [--custom-memory <#G>] : Custom memory usage.
        [-d|--debug] : Debug mode; call out what step the pipeline is on.
        [--temporary </tmp/>] : Directory to save temporary files.
        [--output <./output/>] : Where to save the final output.
        [--logs <./logs/>] : Where to save logs.
        -a|--bam-a : input bam A name.
        -b|--bam-b : input bam B name.
        [--bai-a <APPA.bai>] : Explicitly define bai file for bam a.
        [--bai-b <APPB.bai>] : Explicitly define bai file for bam b."
```
Example:
```
docker run --rm -v ~/ChIPseq_data:/data -it correlation /scripts/runEntirePipeline.sh -a BAM_A.bam -b BAM_B.bam --genome grch38 --temporary /data/
```
Parameters are explained in more detail below.

# Parameters
### Genome
By default, the pipeline assumes it is being provided hg19-aligned ChIP-seq data. The only other available assembly currently is grch38. To specify grch38, use the `--genome` parameter as follows:
```
--genome grch38
```

### Data Directory
For the docker to run properly, a `/data` directory must be mounted that contains BAM_A and BAM_B. In the above example, our data was stored in the `ChIPseq_data` subdirectory. Thus, the command to mount our location data directory to the docker data directory came out to be:
```
-v ${PWD}/ChIPseq_data:/data
```
**This folder must be fully accessible for writing.** By default, all logs and output are printed to `/data/logs` and `/data/output`, so not having access to this folder will cause the pipeline to crash.
Run the command below to allow full write access to your folder:
```
chmod a+w [folder]
```

### Paired End vs Single End
The pipeline requires different input independing on the style of ChIP-seq done. The pipeline now automatically determines whether the data is paired end or single end. If the data is single ended, it uses the first 10,000 reads to calculate an average read length.

To manually specify paired end or single end & read length, use the following commands:

For paired end data, specify the flag `-p`.

For single end data, specify the flag `-l` followed by the average read length. For example, for reads of length 36bp, the parameter would be `-l 36`.

### BAM Files
Parameters `-a` and `-b` are the names of the input BAM files. This should be their name relative to the data directory, so include the names of any subfolders.

For example, say you have BAMs `BAM_A.bam` and `BAM_B.bam` in `~/ChIPseq_data`. Your `-a` and `-b` will look like below:
```
-a BAM_A.bam -b BAM_B.bam
```

### Output Parameters
The location to save the final correlation value is defined using `--output`. By default, it is set to `--output /data/output`, resulting in a directory called `output` being created in your data directory. You may also adjust the locations of any output logs by setting `--logs` (default of `--logs /data/logs`), and any temporary files by setting `--temporary` (default `/tmp/`). If you would like to hide logs, feel free to set `--logs` to `--logs /tmp/`.

### Standard Out
By default, the docker runs in non-debug mode. The only output to stdout will be the final correlation value, the same value saved to the directory defined by `--output`. To enter debug mode, add the flag `-d`. In debug mode, messages representing the state of the pipeline will be printed to stdout.

### Setting Java Memory
This docker uses two igvtools scripts, both of which run using the Java VM. The amount of memory allocated to each VM can be defined by using the `--custom-memory` parameter. For example, to set 1500mb for each VM, use the parameter `--custom-memory 1500m`. For 3GB, use `--custom-memory 3g`. Please note that in double mode (default), two VMs run at once time, so ensure you have enough RAM for `--custom-memory` times two.

### Single Threaded Mode
The parameter `--single-threaded` controls whether or not the pipeline will run in single or double mode. By default, the pipeline will be run on both BAM_A and BAM_B simultaneously. On older machines or weaker VMs, this provides no benefit, so it may be worth adding the `--single-threaded` flag to force them to run one after the other.

### Processing Mint-ChIP Data
Note: Still in testing.

The parameter `-m` marks both .bam files as Mint ChIP data sets. This is required when working with Mint ChIP data, as it tells the pipeline to remove any data overlapping Mint-ChIP specific blacklisted regions.