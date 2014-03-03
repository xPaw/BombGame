var hookshot = require('hookshot');
var exec = require('child_process').exec;
var Rcon = require('rcon');


hookshot('refs/heads/master', function(info){

    console.log('Pulling & compiling');

    exec('./compile_bombgame.sh', function(){

        var conn = new Rcon('127.0.0.1', 27015, 'test');
        conn.on('auth', function(error, stdout, stderr) {
            conn.send('say Received a GitHub hook!;sm plugins reload BombGame');
                conn.disconnect();
            });
        conn.connect();
    });

}).listen(1337)

