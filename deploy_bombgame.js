var hookshot = require('hookshot');
var exec = require('child_process').exec;
var rcon = require('rcon');

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
        
        var conn = new rcon('timmw.no-ip.org', 27015, 'test');

        conn.on('auth', function()
        {
            conn.send('sm plugins refresh;sm plugins reload BombGame');

            setTimeout(function()
            {
                var length = info.commits.length;

                conn.send('say ">> ' + info.pusher.name + ' pushed ' + length + ' commit' + (length === 1 ? '' : 's') + ': ' + info.compare + '"');

                for(var i = 0; i < length; i++)
                {
                    var commit = info.commits[ i ];

                    conn.send('say ">> ' + commit.id.substring(0, 8) + ' | ' + commit.message + '"');
                }

                conn.disconnect();
            }, 1111);
        });

        conn.connect();
    });

}).listen(1337);
