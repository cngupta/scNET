

process_networks = function(list, celltypeTag, th)
{
	newList=list()
	for (i in 1:length(list))
	{
		network=rank_network_edges(as.data.frame(list[i]),th,	celltypeTag)
		colnames(network)=c("edge",paste("rank",i,sep="."))
		name=paste("Network", i, sep = ".")
		newList[[name]]=network
	}
	newList
}

rank_network_edges = function(net,th,tag) #network and threshold for # of edges to report
{
	#rank edges of each network from 1 to n
	colnames(net)=c("regulatoryGene","targetGene","weight")
	net= net %>% filter(regulatoryGene %in% TFs$V1)
	net$edge=paste(net$regulatoryGene,"-",net$targetGene)
	net=net[,3:4]
	net=net[,c(2,1)]
	df=net %>% arrange(-weight) %>% mutate(rank = dense_rank(-weight))
	df=df[1:th,c(1,3)]
	colnames(df)=c("edge",paste(tag,"rank",sep="_"))
	df
}

combine_network_dfs = function(list)
{
	#merge all dfs columwise; NAs if the edge is absent
	df=Reduce(function(x, y) merge(x, y, all=TRUE), list, accumulate=FALSE)
	#replace NAs with a value that is equal to the highest rank +1 for each network
	l=colMax(df)
	for(i in 2:ncol(df))
	{
		n=l[i]
		vars=paste("rank",i-1,sep=".")

		#courtesy https://bit.ly/3pL5Fut
		df=df %>%
			mutate_at(.vars = vars, .funs = funs(ifelse(is.na(.), n, .)))
	}
	rownames(df)=df$edge
	df=df[,2:ncol(df)]
	df[] <- lapply(df, function(x) as.numeric(as.character(x)))
	df
}


colMax = function(data) sapply(data, max, na.rm = TRUE)

ara=function(list, celltypeTag, th) #no. of edges to return
{
	list=list
	tag=celltypeTag
	th=th
	NetList=process_networks(list,celltypeTag,nedges)
	NetworksMatrix=combine_network_dfs(NetList)
	matrix=NetworksMatrix
	ncol=ncol(matrix)
	matrix$mean = rowMeans(matrix)
	matrix=matrix %>% mutate (meanRank = dense_rank(mean)) %>% arrange(meanRank)
	matrix=matrix[1:nedges,]
	matrix$edge=rownames(matrix)
	matrix=matrix[,c("edge","meanRank")]
	rownames(matrix)=c()
	matrix=matrix %>% separate(edge, c("TF","target"),sep="-")
}

get_pageRank=function(net, tag)
{
	net.igraph=graph_from_data_frame(net, directed = TRUE, vertices = NULL)
	pageRank=page_rank(net.igraph)
	pageRank=as.data.frame(pageRank$vector)
	colnames(pageRank)=c("scores")
	pageRank=pageRank[order(-pageRank$scores), , drop = FALSE]
	colnames(pageRank)=paste(tag,"pr",sep=".")
	pageRank$gene=rownames(pageRank)
	rownames(pageRank)=c()
	pageRank
}

calculate_triplet_hubScores=function(loregicOut,hubtbl)
{
	colnames(hubtbl)=c("scores","gene")
	new=loregicOut
	new[] <- hubtbl$scores[match(unlist(loregicOut), hubtbl$gene)] #(reference: https://stackoverflow.com/questions/35636315/replace-values-in-a-dataframe-based-on-lookup-table)
	new$RF1=as.numeric(new$RF1)
	new$RF2=as.numeric(new$RF2)
	new$target=as.numeric(new$target)
	new$Sum=rowSums(new)
	new$triplet=paste(loregicOut$RF1,loregicOut$RF2,loregicOut$target, sep="-")
	new=new %>% arrange(-Sum)
	new
}

find_target_pairs=function(net,th) #network and JI threshold
{
	colnames(net)=c("TF","target","score")
	m=acast(net, TF~target, value.var="score")
	m=t(m)
	m[is.na(m)]=0 #set NA =0
	#find cardinalities
	# Find that paper and add reference
	i12 = m %*% t(m)
	s = diag(i12) %*% matrix(1, ncol = length(diag(i12)))
	u12 = s + t(s) - i12
	jacc= i12/u12
	#genes_jaccard_dist.dat=melt(as.matrix(jacc))
	#target_pairs=genes_jaccard_dist.dat[genes_jaccard_dist.dat[, ncol(genes_jaccard_dist.dat)]>th,]
	#colnames(target_pairs)=c("gene1","gene2","Jaccard")
	#target_pairs$Jaccard=1
	#target_pairs
	jacc[jacc < th] = 0
	jacc[jacc >= th] = 1
	diag(jacc)=1 #required for TOMsimilarity
	jacc
}

detect_modules = function(matrix)
{
	#ref: https://support.bioconductor.org/p/102857/
	#ref:
	TOM = TOMsimilarity(matrix,TOMType="unsigned");
	dissTOM = 1-TOM
	# Call the hierarchical clustering function
	geneTree = flashClust(as.dist(dissTOM),method="average");
	minModuleSize = 10;
	# Module identification using dynamic tree cut:
	dynamicMods = cutreeDynamic(dendro = geneTree,  method="tree", minClusterSize = minModuleSize)
	modules=cbind(as.data.frame(dynamicMods),rownames(matrix))
	modules=modules[,c(2,1)]
	colnames(modules)=c("gene","moduleID")
	modules
}

diff_rewired_targets = function(triplets1, triplets2)
{
	tmp=summary(comparedf(triplets1, triplets2, by = "target"))
	tmp
}