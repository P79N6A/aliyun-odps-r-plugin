#
.onLoad <- function(libname, pkgname)
{
    init.java.env(libname, pkgname)
    maxRecord<<-10000
    errormsg<<-load.errormsg()
    conf<-rodps.loadconf()
    odpsOperator<<-NULL
    if(!is.null(conf)){
        .init_odps_operator(conf)
    }
}
rodps.init <- function(path=NULL, access.id=NULL, access.key=NULL){
    conf<-rodps.loadconf(path)
    if(!is.null(access.id)){
        conf["access_id"] <- access.id;
    }
    if(!is.null(access.key)){
        conf["access_key"] <- access.key;
    }
    if(!is.null(conf)){
        .init_odps_operator(conf)
    }
}


.init_odps_operator <- function(conf){
    if (!is.na(conf["tunnel_endpoint"])) {
        tunnel_endpoint <- conf["tunnel_endpoint"]
    } else if (!is.na(conf["dt_end_point"])) {
        tunnel_endpoint <- conf["dt_end_point"]
    } else {
        tunnel_endpoint <- "NA"
        print("WARN: tunnel_endpoint not set, auto-routed tunnel endpoint might not work")
    }
    odpsOperator <<- .jnew("com/aliyun/odps/rodps/ROdps", conf["project_name"],
                                                          conf["access_id"],
                                                          conf["access_key"],
                                                          conf["end_point"],
                                                          tunnel_endpoint,
                                                          conf["logview_host"],
                                                          conf["log4j_properties"])
    rodps.init.type()
}

init.java.env <- function(libname, pkgname)
{
    library(rJava)
    if ("windows" == .Platform$OS.type)
    {
        .jinit(parameters=c("-Xmx512m", "-Xms512m"))
    }
    else
    {
        .jinit()
    }
    jarPath <- paste(libname, pkgname, "lib", sep = .Platform$file.sep)
    jarFiles <- list.files(jarPath)
    .jaddClassPath(paste(jarPath,"/.",sep=""))
    for (i in 1:length(jarFiles))
    {
        jarFiles[i] <- paste(jarPath, jarFiles[i], sep = .Platform$file.sep)
        if (0 == length(grep("DT", jarFiles[i])))
            .jaddClassPath(jarFiles[i])
    }
    init.dtsdk.env(libname, pkgname)
}

init.dtsdk.env <- function(libname, pkgname)
{
    jarPath <- paste(libname, pkgname, "lib", "DT", sep = .Platform$file.sep)
    jarFiles <- list.files(jarPath)
    for (i in 1:length(jarFiles))
    {
        jarFiles[i]<- paste(jarPath, jarFiles[i], sep = .Platform$file.sep)
        .jaddClassPath(jarFiles[i])
    }
}

rodps.loadconf <- function(path=NULL){
    if(is.null(path)){
        path <- Sys.getenv("RODPS_CONFIG")
    }
	if(is.null(path)){
		path <- Sys.getenv("ODPS_CONFIG")
	}
    if(path == ''){
        path <- paste(Sys.getenv('HOME'),.Platform$file.sep, "odps_config.ini", sep="")
    }
    if (is.null(path) || path=="" || !file.exists(path))
    {
        print("RODPS_CONFIG system variable is not set or the configuration file does not exist, you need to manually init (path)\n,set environment variable or in R workplace")
		return(NULL)
    }
    conf <- read.table(path,stringsAsFactors=FALSE)
    keys<-c()
    values<-c()
    for(i in 1:nrow(conf)){
        row <- conf[i,]
        if( nchar(row)>0 && substr(row,1,1) != '#' ){
            idx <- grep("=", strsplit(row, "")[[1]])[[1]]
            if(length(idx)<1){
                warn("config_error",row)
            }else{
                key = substr(row,1,idx-1)
                value = substr(row,idx+1,nchar(row))
                keys[i] <- key
                values[i] <- value
            }
        }
    }
    names(values)<-keys

    #add access_id/access_key check
    if( is.na(values["access_id"])){
        values["access_id"] <- readline("Please input access_id:")
    }
    if( is.na(values["access_key"])){
        values["access_key"] <- readline("Please input access_key:")
    }
    return(values)
}

rodps.init.type <- function(){                                                                                   
    type.map <- c("integer=int,tinyint,smallint",
                    "numeric=double,float,long,bigint", 
                    "POSIXct=datetime", 
                    "Date=date",
                    "character=string","logical=boolean","factor=string")
    keys1 <- c()
    values1 <- c()
    keys2 <- c()
    values2 <- c()
    i <- 1
    j <- 1
    for(m in unlist(type.map)){
        mp <- strsplit(m, "=")
        vs <- strsplit(unlist(mp)[2],",")
        keys1[i] <- unlist(mp)[1]
        values1[i] <- unlist(vs)[1]
        for(v in unlist(vs)){
            keys2[j] <- v
            values2[j] <- unlist(mp)[1]
            j <- j+1
        }
        i <- i+1
    }
    names(values1) <- keys1
    rodps.type.r2java <<- values1
    names(values2) <- keys2
    rodps.type.java2r <<- values2
} 

rodps.change.types <- function(types){                                                                           
    newtypes <- c()
    i <- 1
    for(t in types){
        newtypes[i] <- rodps.type.java2r[t]
        i <- i+1
    }
    return(newtypes)
}

load.errormsg<-function(){
    keys<-c()
    values<-c()
    names(values)<-keys
    values<-add.errormsg(values,"table_not_found","table not found.")
    values<-add.errormsg(values,"odps_config_ini_missing",
           paste("Can not find odps_config.ini with env variable RODPS_CONFIG, init ODPS environment fail!\n",
           "Please check your odps_config.ini file then re-load RODPS again. \n",
           "\n" ))
    values<-add.errormsg(values,"invalid_value","invalid value")
    values<-add.errormsg(values,"config_error","odps conf error on row ")
    values<-add.errormsg(values,"input_query_error","input query error ")
    values<-add.errormsg(values,"argument_type_error","argument type is wrong ")
    values<-add.errormsg(values,"invalid_project_name","The project name can not be empty ")
    return(values)
}
add.errormsg<-function(errormap,newkey,newvalue){
    idx<-length(errormap)+1
    errormap[idx]<-newvalue
    names(errormap)[idx]<-newkey
    return(errormap)
}
error<-function(error_name,msg=NULL){
    print(geterror(error_name,msg))
}
fatal<-function(error_name,msg=NULL){
    print(geterror(error_name,msg))
}
info<-function(error_name,msg=NULL){
    print(geterror(error_name,msg))
}
warn<-function(error_name,msg=NULL){
    print(geterror(error_name,msg))
}
geterror<-function(error_name,msg=NULL){
    if(is.null(error_name) || error_name==""){
        output=""
    }else if(is.null(errormsg[error_name])){
        output=error_name
    }else{
        output=errormsg[error_name]
    }

    if(!is.null(msg) && msg!=""){
        output<-paste(output,"-",msg)
    }
    return(output)
}
