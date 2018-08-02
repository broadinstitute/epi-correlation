# Histone Modification ChIP Similarity Metric: Correlation
This package provides a method of determining similarity between two Histone Modification ChIP-seq aligned bam files.

## Installing
Download the repository to a local folder; use docker to build the container. Run the following command from the same directory as the Dockerfile:
```
docker build -t correlation .
```

## Usage
Usage Output:
```
docker run --rm -v [data dir]:/data -it correlation /scripts/runEntirePipeline.sh [-p|-l <0-200>] -a <input bam> -b <input bam> [-m </tmp/>] [-o <>] [-s]
```
Example:
```
docker run --rm -v ${PWD}/reference/test_data:/data -it correlation /scripts/runEntirePipeline.sh -p -a /data/BAM_1.bam -b /data/BAM_2.bam -s
```
Parameters are explained in more detail below.

### Data Directory
For the docker to run properly, a `/data` directory must be mounted that contains BAM1 and BAM2. In the above example, our data was stored in `~/cor_docker/reference/test_data`. Thus, the command to mount our location data directory to the docker data directory came out to be:
```
-v ${PWD}/reference/test_data:/data
```
`${PWD}` was used to refer to the current directory at the time of running the docker, which was `~/cor_docker/`. An alternate version of the parameter is below:
```
-v ~/cor_docker/reference/test_data:/data
```

**If this folder does not contain indexing files for your BAMs, it must be fully accessible for writing.** If docker is incapable of writing `.bam.bai` files to this directory, the pipeline will crash.
Run the command below to allow full write access to your folder:
```
chmod a+w [folder]
```

### Paired End vs Single End
The pipeline requires different input independing on the style of ChIP-seq done. If the .bams are paired end, the parameter `-p` is required. If they are single-end, the following parameter is required:
```
-l [read length]
```
For example, for a single-end ChIP seq bam with a read length of 46, the command would be `-l 46`.

### BAM Files
Parameters `-a` and `-b` are the names of the input BAM files. This should be their name relative to root, so including the data directory you've mounted.

For example, say you have BAMs `BAM_1.bam` and `BAM_2.bam` in `~/cor_docker/reference/test_data`. Your `-a` and `-b` will look like below:
```
-a /data/BAM_1.bam -b /data/BAM_2.bam
```

**Put simply,** for `-a` and `-b`, take the name of your BAM files, and prepend with `/data/`.

### Output Parameters
There are 2 different parameters controlling output. 

The parameter `-s` determines whether or not the final correlation value is printed to stdout in completion. Use this flag if you are saving the output to a file yourself, or if you just want to see the correlation.

The parameter `-o` determines where the cor_out.txt file is saved. If you want the pipeline to automatically save the correlation to a file where you can access it after the pipeline is complete, the only valid option is as follows:
```
-o /data/
```
The cor_out.txt file will be available in your `~/cor_docker/reference/test_data` directory.

### Midpoint Directory
Most of the time, you can ignore this parameter.
By default, all mid-pipeline files are saved to the docker's `/tmp/` directory. This is a special directory that allows for faster reading and writing of files. However, if your machine has low RAM, or you want to be able to later access these files, you can change this folder.

To access these files later, use:
```
-m /data/
```

To simply remove them from the `/tmp/` folder, use:
```
-m /scripts/
```