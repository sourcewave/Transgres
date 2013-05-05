
#include <stdio.h>
#include <jni.h>
#ifdef __APPLE__
#undef false
#undef true
#include <libproc.h>
#endif
#include <errno.h>
#include <limits.h>
#include <syslog.h>
#include <unistd.h>
#include <dirent.h>
#include <string.h>
#include <stdlib.h>

JNIEnv *env;
JavaVM* s_javaVM = NULL;
JNIEnv* jniEnv;

JavaVMOption options[20];


// the postgres server datadir
char *DataDir = "/tmp";
extern void doJVMinit(void);

static char *getPGdir() {
    // WARNING: this code will only work on linux or OS X
#ifdef __APPLE__
    char pathbuf[PROC_PIDPATHINFO_MAXSIZE];
    int pid = getpid();
    int ret = proc_pidpath(pid, pathbuf, PROC_PIDPATHINFO_MAXSIZE);
    if ( ret <= 0 ) {
        syslog(LOG_ERR, "PID %d: proc_pidpath ();\n", pid);
        syslog(LOG_ERR, "    %s\n", strerror(errno));
    } else {
        syslog(LOG_ERR, "proc %d: %s\n", pid, pathbuf);
    }
    
#else
    char pathbuf[PATH_MAX];
    const char* exe_sym_path = "/proc/self/exe";
    // when BSD: /proc/curproc/file
    // when Solaris: /proc/self/path/a.out
    // Unix: getexecname(3)
    ssize_t ret = readlink(exe_sym_path, pathbuf, PATH_MAX);
    if (ret == PATH_MAX || ret == -1) {
        syslog(LOG_ERR, "Getting executable path: %s\n",strerror(errno));
    } else {
        pathbuf[ret] = '\0';
    }
#endif
    char *lst = strrchr(pathbuf,'/'); // last slash in path
    long n = lst-pathbuf;
    return strndup(pathbuf, n);
}



static char *getClasspath() {
    char buf[50000];
    char *pbuf = getPGdir();
    /* get all the jar fles in the jar directory and append? */
    snprintf(buf, 10000, "-Djava.class.path=%s/../lib/pg_jinx.jar:%s/../lib/pljava.jar", pbuf,pbuf);
    
    char zbuf[4096];
    struct dirent *ep;
    
    snprintf(zbuf, 4096, "%s/../ext",DataDir);
    
    // Get all the jars in the ext directory
    DIR *dp = opendir(zbuf);
    if (dp != NULL) {
        while ( (ep = readdir(dp))) {
            long n = strlen(ep->d_name);
            if (n < 5) continue;
            if ( strcmp(ep->d_name+n-4, ".jar") == 0) {
                snprintf(zbuf,4096,":%s/../ext/%s",DataDir,ep->d_name);
                strlcat(buf, zbuf, 50000);
            }
        }
        (void) closedir (dp);
    }
    
    syslog(LOG_ERR, "classpath = %s\n", buf);
    return strdup(buf);
}


int main(int argc, const char * argv[]) {    
    jsize nVMs;
    JavaVM *vmBuf[2];
    JNI_GetCreatedJavaVMs(vmBuf, 2, &nVMs);
    if (nVMs > 0) {
        s_javaVM = vmBuf[0];
        (*s_javaVM)->GetEnv(s_javaVM, (void **)&env, JNI_VERSION_1_6);
        jniEnv = env;
        return 0;
    }
    
    jint jstat;
    int debug_port = 0;
    
    JavaVMInitArgs vm_args;
    const char *dbp;
    
    int ox = 0;
    options[ox++].optionString = getClasspath();
    
 	if (debug_port != 0) {
        char buf[4096];
        sprintf(buf, "-Xrunjdwp:transport=dt_socket,server=y,suspend=%s,address=localhost:%d", debug_port > 0 ? "n" : "y", abs(debug_port)) ;
        options[ox++].optionString = "-Xdebug";
        options[ox++].optionString = strdup(buf);
    }
    char *javahome = "/Volumes/Storage/Repositories/Postgres/Transgres/Vendor/jdk1.7.jdk/Contents/Home/jre";
//    options[ox++].optionString = "-XstartOnFirstThread";
    { char buf[4096];
        sprintf(buf, "-Djava.home=%s", javahome);
        options[ox++].optionString = strdup(buf);
    }
    { char buf[4096];
         sprintf(buf, "-Dsun.boot.library.path=%s/lib", javahome);
        options[ox++].optionString = strdup(buf);
    }
    { char buf[4096];
        sprintf(buf, "-Djava.ext.dirs=%s/lib/ext", javahome);
        options[ox++].optionString = strdup(buf);
    }
/*    { char buf[4096];
        sprintf(buf, "-Dsun.boot.class.path=%s/lib/resources.jar:%s/lib/rt.jar:%s/lib/sunrsasign.jar:%s/lib/jsse.jar:%s/lib/jce.jar:%s/lib/charsets.jar:%s/lib/jfr.jar:%s/lib/JObjC.jar:%s/classes", javahome,javahome,javahome,javahome,javahome,javahome,javahome,javahome);
        options[ox++].optionString = strdup(buf);
    }
*/
    { char buf[4096];
        sprintf(buf, "-Dsun.boot.class.path=%s/lib/resources.jar:%s/lib/rt.jar:%s/lib/sunrsasign.jar:%s/lib/jsse.jar:%s/lib/jce.jar:%s/lib/charsets.jar:%s/lib/jfr.jar:%s/lib/JObjC.jar:%s/classes", javahome,javahome,javahome,javahome,javahome,javahome,javahome,javahome);
        options[ox++].optionString = strdup(buf);
    }
	
    options[ox++].optionString = "-Djava.awt.headless=true";

    { char buf[4096];
        char *pbuf = getPGdir();
        sprintf(buf, "-Djava.library.path=%s/../lib", pbuf /*, STRINGIZE2(JLIB_PATH) */ );
        options[ox++].optionString = strdup(buf);
        free(pbuf);
	}
	
    /*  Zapped out -- shouldn't set java.ext.dirs -- breaks things
     {
     char buf[4096];
     char *pbuf = getPGdir();
     // If I zap the extdirs -- I need to include the security dir again
     // Why do I need to include the class path in the ext dir list?
     snprintf(buf, 4096, "-Djava.ext.dirs=%s/../ext:%s/../lib:%s/../../PlugIns/jdk1.7.jdk/Contents/Home/jre/lib/ext",DataDir,pbuf,pbuf);
     // options[ox++].optionString = pstrdup(buf);
     pfree(pbuf);
     }
     */
    
    { char buf[4096];
        snprintf(buf, 4096, "-Djinx.extDir=%s/../ext",DataDir);
        options[ox++].optionString=strdup(buf);
    }
    
	vm_args.version = JNI_VERSION_1_6;
	vm_args.options = options;
	vm_args.ignoreUnrecognized = JNI_FALSE;
    vm_args.nOptions=ox;

	jstat = JNI_CreateJavaVM(&s_javaVM, (void **) &env, &vm_args);
    jniEnv = env;
	if (jstat == JNI_OK && (*env)->ExceptionCheck(env)) {
        printf("Java VM threw exception during startup\n");
        // jthrowable jt = (*env)->ExceptionOccurred(env);

        /*        if (jt != 0) {
         
         (*env)->ExceptionClear(env);
         (*env)->CallVoidMethod(env, jt, printStackTrace);
         elogExceptionMessage(env, jt, WARNING);
         }
         */
        jstat = JNI_ERR;
    }
    if (jstat != JNI_OK) { printf("Failed to create Java VM\n"); }
    return 0;
}
