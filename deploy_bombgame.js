var hookshot = require('hookshot');
var exec = require('child_process').exec;
var rcon = require('rcon');

var host = 'timmw.no-ip.org', port = 27015, rconPassword = 'test';

console.log('Pulling latest changes...');

exec('git pull', function(error, stdout, stderr){

    console.log('stdout: ' + stdout);
    console.log('stderr: ' + stderr);

    if (error !== null)
    {
        console.log('exec error: ' + error);
    }

    console.log('Waiting for call from github webhook...');
    
    hookshot('refs/heads/master', function(info)
    {
        console.log('Pulling & compiling');

        exec('bash compile_bombgame.sh', function(error, stdout, stderr)
        {
            console.log('stdout: ' + stdout);
            console.log('stderr: ' + stderr);

            if (error !== null)
            {
                console.log('exec error: ' + error);
            }
            
            var conn = new rcon(host, port, rconPassword);

            conn.on('auth', function()
            {
                conn.send('sm plugins refresh;sm plugins reload BombGame');

                setTimeout(function()
                {
                    var length = info.commits.length;

                    conn.send('say ' + info.pusher.name + ' pushed ' + length + ' commit' + (length === 1 ? '' : 's') + ': ' + info.compare;

                    for(var i = 0; i < length; i++)
                    {
                        var commit = info.commits[ i ];

                        conn.send('say >> ' + commit.message);
                    }

                    conn.disconnect();
                }, 1111);
            });

            conn.connect();
        });

    }).listen(1337);
})