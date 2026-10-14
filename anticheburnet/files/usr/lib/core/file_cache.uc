// Reuse hashes only for unchanged files outside the coarse timestamp window.
let fs = require("fs");

function identity(path) {
    let stat = fs.stat(path);
    if (stat == null || stat.type != "file") return null;
    return {
        signature: join(":", [path,stat.dev.major,stat.dev.minor,stat.inode,stat.size,stat.mtime,stat.ctime]),
        recent: time() - (stat.mtime > stat.ctime ? stat.mtime : stat.ctime) <= 2
    };
}

function ensure_parent(path) {
    let slash = rindex(path,"/");
    if (slash <= 0) return true;
    let parent = substr(path,0,slash);
    return fs.stat(parent) != null || (ensure_parent(parent) && (fs.mkdir(parent,0755) || fs.stat(parent) != null));
}

function write_record(path,value) {
    if (!ensure_parent(path)) return;
    let stamp=clock(),temporary=path+"."+stamp[0]+"."+stamp[1];
    let file=fs.open(temporary,"w",0600);
    if (!file) return;
    let written=file.write(sprintf("%J\n",value));
    file.close();
    if (written == null || !fs.rename(temporary,path)) fs.unlink(temporary);
}

function digest(path,cache_path) {
    let before=identity(path);
    if (before == null) return "";
    if (!before.recent) {
        try {
            let cached=json(fs.readfile(cache_path));
            if (cached.format == 1 && cached.signature == before.signature && match(cached.digest || "",/^[a-f0-9]{64}$/))
                return cached.digest;
        } catch (error) {}
    }
    let quoted="'"+replace(path,/'/g,"'\\''")+"'";
    let pipe=fs.popen("sha256sum "+quoted+" 2>/dev/null","r");
    if (!pipe) return "";
    let output=pipe.read("all"),status=pipe.close();
    let result=substr(output || "",0,64),after=identity(path);
    if (status != 0 || !match(result,/^[a-f0-9]{64}$/) || after == null || before.signature != after.signature) return "";
    write_record(cache_path,{format:1,signature:after.signature,digest:result});
    return result;
}

return { identity, digest };
