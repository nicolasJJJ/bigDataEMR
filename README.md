BROUILLON

## Sommaire
1. [Prérequis](#prérequis)
2. [Installation](#installation)
3. [Usage](#usage)
4. [Développement](#développement)
5. [Tests](#tests)
6. [Infrastructure](#infrastructure)
7. [Licence](#licence)
8. [Contact](#contact)

# Prérequis
- Croire au gain de temps, au business, et au cloud AWS, même si c'est sans doutes surveillé par la NSA. Au moins, ça détruit pas ton business quand ça brûle (oups)
- AWS CLI configuré
- Credentials AWS en secrets (rôle et ID)
- Terraform v1.x
- Python 3.8+
- Clé Kaggle sur SSM (AWS)

# Installation

1/ lancer github Actions ou créer un bucket s3 + insérer 'script.py' dans bucket/src. Voir main.yaml.

côté terraform, considérant que vous avez déjà votre bucket de configuré

```
cd terraform
terraform init
terraform apply -auto-approve
```


# Usage

Cher recruteur, cher techlead, cher inconnu,

Le but de ce travail est de déployer de A à Z un simple script spark dans un cluster EMR créé par Terraform.
On va bien prouver que vos process internes et que votre cluster Oracle installé sur votre data center de 2008 pue du cul, sauf si vous êtes Américain. Au moins, faites un effort, installez Outpost.

NOTE : J'ai supprimé l'historique de mes branches car je ne souhaite pas afficher mon ID AWS, bien que la documentation indique que ce n'est pas une faille de sécurité. Mais j'ai préféré en effet les garder dans les Secrets. J'ai ce petit côté paranoïaque. Mais rassure toi, je ne m'habille pas encore avec de l'aluminium.

# Développement

## script.py

L'objectif est de lire un extrait de The Pile (~50Go), au format jsonL, d'effectuer un nettoyage et une partition. Les données seront stockées sur S3 au format .parquet afin de pouvoir être lues par Athena.

C'EST FINI LE CSV, VOUS COMPRENEZ ??? SI VOUS ME RECRUTEZ ET QUE JE VOIS DES TRAITEMENTS DE CSV SANS TRANSFORMATION EN PARQUET, JE PRENDS DU GALLON ET VOUS ETES VIRE !! 

Le script télécharge en premier lieu une clé d'API de Kaggle afin de télécharger le dataset.

Les tests sont là pour s'assurer que les transformations se font.

## main.yaml

Créée et configure un bucket S3 sur AWS contenant le script qui sera exécuté par EMR. Le bucket sert aussi de répertoire aux résultats du traitement. Si le bucket existe déjà ? Bah oui, je suis développeur, pas un junior qu'on emmène dans un afterwork au lieu de l'amener dans une salle de sport. 

## main.tf

On se sent terraformeur ? On utilise Terraform.
Crée : le VPC, les sous-réseaux publics (pour télécharger le fichier Kaggle) et privés, les Gateways et le Gateway Endpoint pour faire réseau privé <-> S3. Car je suis certifié SAA-C03, merde.
On configure les rôles, les clés, les groupes de sécurité, etc... 
On upload le script, on initie le spark action,
et HOP ! 


# tests

# infrastructure

# licence

MIT License

Copyright (c) [2025] [nicolasJJJ]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

# contact

Retrouve moi sur [LinkedIn](https://www.linkedin.com/in/n-jandot/)

## Qui es-tu ?

Un recruteur ? Te bile pas, pour toi c'est du chinois. 

Un dev/tech-lead ? J'espère que t'aimes mon humour pince-sans-rire. Et que tu me recruteras. Mais t'inquiète petit, au téléphone je reste pro. J'ai pas encore l'ancienneté pour la jouer Jean Gabin.

Un galérien à la recherche d'une config EMR ? Vas-y bonhomme, c'est ma manière de contribuer à ce que tu ne me sortes pas des dingueries sur ton cluster.

Et si ça marche pas ? Bienvenue dans le métier, lis les logs : tu est officiellement "Clusterf*cked".
