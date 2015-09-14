var marked = require('marked');

function getStdin(callback) {
    var stdin = process.stdin
        , buff = '';

    stdin.setEncoding('utf8');

    stdin.on('data', function(data) {
        buff += data;
    });

    stdin.on('error', function(err) {
        return callback(err);
    });

    stdin.on('end', function() {
        return callback(null, buff);
    });

    try {
        stdin.resume();
    } catch (e) {
        callback(e);
    }
}

function parse(markdownString) {

// Async highlighting with pygmentize-bundled
    marked.setOptions({
        highlight: function (code, lang, callback) {
            require('pygmentize-bundled')({lang: lang, format: 'html'}, code, function (err, result) {
                callback(err, result.toString());
            });
        }
    });

// Using async version of marked
    marked(markdownString, function (err, content) {
        if (err) throw err;
        console.log(content);
    });
}

getStdin(function(err, buf) {
    if (err) {
        return;
    }
    parse(buf.toString());
});