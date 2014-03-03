#!/bin/sh

git pull

spcomp BombGame
spcomp WallCreator
spcomp SpawnEditor

cp *.smx D:/SteamCMD/cs_go/csgo/addons/sourcemod/plugins/
rm *.smx

cp addons D:/SteamCMD/cs_go/csgo/ -R
cp cfg D:/SteamCMD/cs_go/csgo/ -R
cp maps D:/SteamCMD/cs_go/csgo/ -R
cp resource D:/SteamCMD/cs_go/csgo/ -R