 #!/bin/bash

# obtain parameters
bam=$1
read_length=$2
discordant_z=$3
back_distance=$4
weight=$5
min_mapping_threshold=$6
lumpy_vcf=$7
gt_vcf=$8
threads=$9

# locate lumpy scripts directory
scripts="lumpy-sv/scripts"

# index bam file
samtools index -@ "${threads}" "${bam}"
echo "sample indexed" 1>&2
echo "${bam}"

# extract the discordant paired-end alignments.
samtools view -@ "${threads}" -b -F 1294 "${bam}" > sample.discordant.bam
echo "discordant reads extracted" 1>&2

# extract the split-read alignments
samtools view -@ "${threads}" -h "${bam}" | "${scripts}"/extractSplitReads_BwaMem -i stdin | samtools view -@ "${threads}" -Sb - > sample.split.bam
echo "split reads extracted" 1>&2

# sort both alignments
samtools sort -@ "${threads}" sample.discordant.bam > sample.discordant.sorted.bam
samtools index -@ "${threads}" sample.discordant.sorted.bam
echo "discordant reads sorted" 1>&2

samtools sort -@ "${threads}" sample.split.bam > sample.split.sorted.bam
samtools index -@ "${threads}" sample.split.sorted.bam
echo "split reads sorted" 1>&2

# generate empirical insert size statistics on each library in the BAM file 
samtools view -@ "${threads}" "${bam}" | "${scripts}"/pairend_distro.py -r "${read_length}" -X 4 -N 10000 -o sample.lib.histo > tmp.out 2>&1
cat tmp.out
mean=`tail -1 tmp.out | cut -f1 | cut -f2 -d ':' | cut -f1 -d '.'`
std=`tail -1 tmp.out | cut -f2 | cut -f2 -d ':' | cut -f1 -d '.'`
echo "library statistics generated" 1>&2
echo "${mean}"
echo "${std}"

echo "$(pwd)"

# lumpy call (traditional)
lumpy -mw 4 -tt 0 \
-pe id:"sample",bam_file:"sample.discordant.sorted.bam",histo_file:"sample.lib.histo",mean:"${mean}",stdev:"${std}",read_length:"${read_length}",min_non_overlap:"${read_length}",discordant_z:"${discordant_z}",back_distance:"${back_distance}",weight:"${weight}",min_mapping_threshold:"${min_mapping_threshold}" \
-sr id:sample,bam_file:sample.split.sorted.bam,back_distance:"${back_distance}",weight:"${weight}",min_mapping_threshold:"${min_mapping_threshold}" \
> "${lumpy_vcf}"
echo "lumpy call finished" 1>&2

# post procesing with SVTyper to make GT Calls from the Lumpy vcf  using a Bayesian maximum likelihood algorithm.
svtyper-sso -B "${bam}" -S sample.split.sorted.bam -i "${lumpy_vcf}" --max_reads 2000 --core "${threads}" > "${gt_vcf}"
echo "svtyper call finished" 1>&2