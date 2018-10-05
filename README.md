# Histone Modification ChIP Similarity Metric: Correlation
This package provides a method of determining similarity between two Histone Modification ChIP-seq **hg19** aligned bam files.

# Using This Docker
## Installing
Download the repository to a local folder; use docker to build the container. Run the following command from the same directory as the Dockerfile:
```
docker build -t correlation .
```

## Testing
The docker automatically tests itself upon complication. You should see the following output somewhere in the docker output:
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
docker run --rm -v [data dir]:/data -it correlation /scripts/runEntirePipeline.sh -a <input bam> -b <input bam> [-t </tmp/>] [-o </data/output>] [-x </data/logs>] [-d] [-m [0-9]+(m|g)] [-s]
```
Example:
```
docker run --rm -v ~/ChIPseq_data:/data -it correlation /scripts/runEntirePipeline.sh -a /data/BAM_A.bam -b /data/BAM_B.bam
```
Parameters are explained in more detail below.

# Parameters
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
The location to save the final correlation value is defined using `-o`. By default, it is set to `-o /data/output`, resulting in a directory called `output` being created in your data directory. You may also adjust the locations of any output logs by setting `-x` (default of `-x /data/logs`), and any temporary files by setting `-t` (default `/tmp/`). If you would like to hide logs, feel free to set `-x` to `-x /tmp/`.

### Standard Out
By default, the docker runs in non-debug mode. The only output to stdout will be the final correlation value, the same value saved to the directory defined by `-o`. To enter debug mode, add the flag `-d`. In debug mode, messages representing the state of the pipeline will be printed to stdout.

### Setting Java Memory
This docker uses two igvtools scripts, both of which run using the Java VM. The amount of memory allocated to each VM can be defined by using the `-m` parameter. For example, to set 1500mb for each VM, use the parameter `-m 1500m`. For 3GB, use `-m 3g`. Please note that in double mode (default), two VMs run at once time, so ensure you have enough RAM for `-m` times two.

### Single Threaded Mode
The parameter `-s` controls whether or not the pipeline will run in single or double mode. By default, the pipeline will be run on both BAM_A and BAM_B simultaneously. On older machines or weaker VMs, this provides no benefit, so it may be worth adding the `-s` flag to force them to run one after the other.

### Processing Mint-ChIP Data
Note: Still in testing.

The parameter `-n` marks both .bam files as Mint ChIP data sets. This is required when working with Mint ChIP data, as it tells the pipeline to remove any data overlapping Mint-ChIP specific blacklisted regions. For now, the parameter `-p` is still required to mark the data as paired-end.