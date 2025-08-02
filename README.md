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

- AWS CLI configuré
- Credentials AWS en secrets (rôle et ID)
- Terraform v1.x
- Python 3.8+
- Clé Kaggle sur SSM (AWS)
- Clé 

# Installation

1/ lancer github Actions ou créer un bucket s3 + insérer 'script.py' dans bucket/src. Voir main.yaml.

côté terraform, considérant que vous avez déjà votre bucket de configuré

```
cd terraform
terraform init
terraform import aws_kms_key.emr <votre-cle-pour-EMR>
terraform apply -auto-approve
```


# Usage

Le but de ce travail est de déployer de A à Z un simple script spark dans un cluster EMR (Elastic Map Reduce) créé par Terraform.

NOTE : J'ai supprimé l'historique de mes branches car je ne souhaite pas afficher mon ID AWS, bien que la documentation indique que ce n'est pas une faille de sécurité. Mais j'ai préféré en effet les garder dans les Secrets. 

# Développement

## script.py

L'objectif est de lire un extrait de The Pile (~50Go), au format jsonL, d'effectuer un nettoyage et une partition. Les données seront stockées sur S3 au format .parquet afin de pouvoir être lues par Athena.


Le script télécharge en premier lieu une clé d'API de Kaggle afin de télécharger le dataset.

Les tests sont là pour s'assurer que les transformations se font.

## main.yaml

Créée et configure un bucket S3 sur AWS contenant le script qui sera exécuté par EMR. Le bucket sert aussi de répertoire aux résultats du traitement. Si le bucket existe déjà ? Le processus de création ne sera pas fait et passera à l'étape suivante.

## main.tf

On se sent terraformeur ? On utilise Terraform.
Crée : le VPC, les sous-réseaux publics (pour télécharger le fichier Kaggle) et privés, les Gateways et le Gateway Endpoint pour faire réseau privé <-> S3..
On configure les rôles, les clés, les groupes de sécurité, etc... 
On upload le script, on initie le spark action.


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
