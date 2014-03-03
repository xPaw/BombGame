var hookshot = require('hookshot');
var exec = require('child_process').exec;
var Rcon = require('rcon');


hookshot('refs/heads/master', function(info){

    console.log('Pulling & compiling');


    exec('./compile_bombgame.sh', function(error, stdout, stderr){
        console.log('stdout: ' + stdout);
        console.log('stderr: ' + stderr);
        if (error !== null) {
          console.log('exec error: ' + error);
        }
        var conn = new Rcon('timmw.no-ip.org', 27015, 'test');
        conn.on('auth', function(error, stdout, stderr) {
            conn.send('say Received a GitHub hook!;sm plugins reload BombGame');
                conn.disconnect();
            });
        conn.connect();
    });

}).listen(1337)

