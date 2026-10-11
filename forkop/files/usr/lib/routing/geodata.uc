// Minimal protobuf reader for the published V2Ray/Xray DAT schema. Selected
// entries become native sing-box matchers; no Python/Go helper is installed.
let fs = require("fs");
let ip = require("core.ip");

function varint(reader) {
    let result = 0, factor = 1;
    for (let i = 0; i < 10; i++) {
        if (reader.pos >= length(reader.data)) die("Truncated geodata integer\n");
        let byte = ord(reader.data, reader.pos++);
        result += (byte & 127) * factor;
        if (!(byte & 128)) return result;
        factor *= 128;
    }
    die("Invalid geodata integer\n");
}

function fields(data, callback) {
    let reader = { data, pos: 0 };
    while (reader.pos < length(data)) {
        let header = varint(reader), field = int(header / 8), wire = header & 7, value;
        if (!field) die("Invalid geodata field\n");
        if (wire == 0) value = varint(reader);
        else if (wire == 2) {
            let size = varint(reader);
            if (size > length(data) - reader.pos) die("Truncated geodata field\n");
            value = substr(data, reader.pos, size);
            reader.pos += size;
        }
        else if (wire == 1 || wire == 5) {
            reader.pos += wire == 1 ? 8 : 4;
            if (reader.pos > length(data)) die("Truncated geodata field\n");
        }
        else die("Unsupported geodata wire type\n");
        callback(field, wire, value);
    }
}

function cidr(data) {
    let address = null, prefix = 0;
    fields(data, function(field, wire, value) {
        if (field == 1 && wire == 2) address = value;
        if (field == 2 && wire == 0) prefix = value;
    });
    let parts = [], size = length(address || "");
    if (size != 4 && size != 16) die("Invalid geodata IP size\n");
    for (let i = 0; i < size; i += size == 4 ? 1 : 2)
        push(parts, size == 4 ? sprintf("%d", ord(address, i)) : sprintf("%x", ord(address, i) * 256 + ord(address, i + 1)));
    let result = join(size == 4 ? "." : ":", parts) + "/" + prefix;
    if (!ip.valid_ip_cidr(result)) die("Invalid geodata CIDR\n");
    return result;
}

function domain(data, attribute) {
    let kind = 0, value = "", attributes = {};
    fields(data, function(field, wire, item) {
        if (field == 1 && wire == 0) kind = item;
        if (field == 2 && wire == 2) value = item;
        if (field == 3 && wire == 2) {
            let key = "", enabled = false;
            fields(item, function(number, format, v) {
                if (number == 1 && format == 2) key = v;
                if ((number == 2 || number == 3) && format == 0) enabled = v != 0;
            });
            attributes[key] = enabled;
        }
    });
    if (attribute && !attributes[attribute]) return null;
    let key = [ "domain_keyword", "domain_regex", "domain_suffix", "domain" ][kind];
    if (key == null || value == "") die("Invalid geodata domain\n");
    return { key, value };
}

function convert(data, kind, code) {
    let parts = split(lc(code), "@"), wanted = parts[0], attribute = parts[1];
    if (length(parts) > 2 || (kind == "geoip" && attribute)) die("Unsupported geodata attribute\n");
    let result = {}, found = false;
    // Entry fields are read irrespective of protobuf serialization order.
    fields(data, function(field, wire, entry) {
        if (field != 1 || wire != 2) return;
        let name = "", inverse = false;
        fields(entry, function(number, format, value) {
            if (number == 1 && format == 2) name = lc(value);
            if (kind == "geoip" && number == 3 && format == 0) inverse = value != 0;
        });
        if (name != wanted) return;
        if (inverse) die("Inverse geoip entries are not supported\n");
        found = true;
        fields(entry, function(number, format, value) {
            if (number != 2 || format != 2) return;
            let item = kind == "geoip" ? { key: "ip_cidr", value: cidr(value) } : domain(value, attribute);
            if (item == null) return;
            if (result[item.key] == null) result[item.key] = [];
            push(result[item.key], item.value);
        });
    });
    if (!found || !length(keys(result))) die("Requested geodata entry is missing or empty\n");
    return result;
}

function quote(value) { return "'" + replace(value, /'/g, "'\\''") + "'"; }

function load(url, directory, kind) {
    if (type(url) != "string" || !match(url, /^https?:\/\//) || match(url, /[\r\n]/) || index(url, chr(0)) >= 0)
        die("Geodata URL must use HTTP(S)\n");
    // The cache is under /tmp; URL identity prevents reuse of another provider's DAT.
    fs.mkdir(directory, 0700);
    let path = directory + "/" + kind + ".dat", identity = path + ".url";
    let stat = fs.stat(path);
    if (stat != null && time() - stat.mtime < 604800 && fs.readfile(identity) == url)
        return fs.readfile(path);
    let temp = path + ".download";
    let status = system("umask 077; curl --fail --silent --show-error --location --proto '=http,https' --proto-redir '=http,https' --connect-timeout 10 --max-time 180 --max-filesize 33554432 -o " + quote(temp) + " -- " + quote(url));
    let data = fs.readfile(temp);
    if (status != 0 || data == null || !length(data) || length(data) > 33554432) {
        fs.unlink(temp);
        die("Happ geodata download failed; retaining the previous runtime configuration\n");
    }
    // Validate protobuf before atomically replacing the last good download.
    fields(data, function(field, wire, value) {});
    if (!fs.rename(temp, path)) die("Unable to save RAM geodata cache\n");
    fs.writefile(identity, url);
    return data;
}

return { convert, load };
