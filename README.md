# BigData EMR & AWS Fargate Project

Ce projet illustre le déploiement de bout en bout d'un pipeline Big Data sur AWS. Il intègre le téléchargement de données volumineuses via AWS Fargate, leur stockage sur Amazon S3, et leur traitement distribué avec Apache Spark sur un cluster Amazon EMR provisionné automatiquement par Terraform.

## Sommaire
1. [Architecture](#architecture)
2. [Prérequis](#prérequis)
3. [Structure du Projet](#structure-du-projet)
4. [Installation & Déploiement](#installation--déploiement)
5. [Usage](#usage)
6. [Tests](#tests)
7. [Licence](#licence)
8. [Contact](#contact)

## Architecture

Le pipeline de données est organisé en plusieurs étapes (Architecture Medallion) :

```mermaid
graph TD
    classDef source fill:#f9f,stroke:#333,stroke-width:2px;
    classDef compute fill:#f96,stroke:#333,stroke-width:2px;
    classDef storage fill:#6cf,stroke:#333,stroke-width:2px;
    classDef config fill:#ccc,stroke:#333,stroke-width:2px;

    %% Data Source
    Kaggle[("Kaggle Dataset<br>(The Pile - JSONL)")]:::source

    %% Ingestion
    Fargate["AWS Fargate<br>(Ingestion Container)"]:::compute

    %% Storage
    subgraph Data Lake S3
        S3Bronze[("S3 Bronze<br>(Raw JSONL)")]:::storage
        S3Gold[("S3 Gold<br>(Clean Parquet)")]:::storage
    end

    %% Processing
    EMR["Amazon EMR<br>(Apache Spark Job)"]:::compute

    %% IaC & Code
    TF["Terraform<br>(IaC Provisioning)"]:::config
    GH["GitHub Actions<br>(Code Sync)"]:::config

    %% Data Flow
    Kaggle -->|Téléchargement| Fargate
    Fargate -->|Upload Raw Data| S3Bronze
    S3Bronze -->|Lecture / Traitement| EMR
    EMR -->|Sauvegarde Partitionnée| S3Gold

    %% Infra Flow
    TF -.->|Provisionne| EMR
    TF -.->|Configure| Data Lake S3
    GH -.->|Upload Scripts| Data Lake S3
```

1. **Ingestion (Fargate) -> Bronze (S3)** : Un conteneur s'exécutant sur AWS Fargate télécharge un extrait du dataset *The Pile* (~50Go) depuis Kaggle (format JSONL) et l'upload sur S3. L'utilisation de Fargate est privilégiée à Lambda en raison des limitations de temps de traitement et de ressources de ce dernier.
2. **Bronze -> Silver -> Gold (Spark sur EMR)** : 
   - Nettoyage et conversion des données.
   - Filtrage du texte et partitionnement selon les métadonnées.
   - Les données finales sont stockées sur S3 au format `.parquet`, optimisées et prêtes à être requêtées avec Amazon Athena.
3. **Infrastructure as Code (Terraform)** : Création d'un VPC sécurisé, de sous-réseaux publics/privés, d'un Gateway Endpoint pour S3, des rôles et clés IAM/KMS, et du cluster EMR.

## Prérequis

- AWS CLI installé et configuré
- Credentials AWS configurés en secrets (ID et Rôle)
- Clé d'API Kaggle stockée dans AWS Systems Manager (SSM) paramètre `/kaggle/username` et `/kaggle/key`
- Terraform `v1.x`
- Python `3.8+`
- Docker (pour l'image Fargate)

## Structure du Projet

- `code/` : Scripts de transformation PySpark (nettoyage, transformation, partitionnement). Contient également des tests unitaires pour valider les transformations.
- `fargate/` : Script Python et Dockerfile pour authentifier le compte Kaggle, télécharger les données et les envoyer sur le bucket S3 "Bronze".
- `terraform/` : Fichiers IaC définissant l'infrastructure AWS complète (Réseau, EMR, IAM, Sécurité, etc.).
- `.github/workflows/` : Pipeline CI/CD GitHub Actions pour automatiser la configuration du bucket S3, l'upload des scripts d'exécution et potentiellement le déploiement.

## Installation & Déploiement

### 1. Fargate (Ingestion)

Construisez et poussez l'image Docker contenant le script d'ingestion vers Amazon ECR :

```bash
# Créer le repository ECR
aws ecr create-repository --repository-name emr-project

# Taguer et pousser l'image (remplacez aws_account_id et image_id)
docker tag <image_id> <aws_account_id>.dkr.ecr.eu-west-3.amazonaws.com/emr-project:latest
docker push <aws_account_id>.dkr.ecr.eu-west-3.amazonaws.com/emr-project:latest
```

### 2. Infrastructure (Terraform)

Assurez-vous d'avoir un bucket S3 préconfiguré pour stocker l'état Terraform (si applicable) et les scripts.

```bash
cd terraform
terraform init
# Import de la clé KMS si existante
terraform import aws_kms_key.emr <ARN-de-la-cle-kms>
terraform apply -auto-approve
```

### 3. CI/CD

L'utilisation de GitHub Actions (`main.yaml`) automatise la création d'un bucket S3 (s'il n'existe pas) et y place les fichiers contenus dans `code/`.

## Usage

L'objectif de ce travail est de déployer de A à Z un script Spark dans un cluster EMR (Elastic Map Reduce) créé par Terraform.
Une fois l'infrastructure montée par Terraform, le cluster EMR s'initialise, télécharge les scripts depuis S3, exécute le job PySpark et écrit les résultats transformés et partitionnés sur S3.

*Note : L'historique Git des branches a été expurgé volontairement afin de ne pas exposer d'identifiants AWS (bien qu'ils soient désormais externalisés dans des secrets).*

## Tests

Des tests unitaires (TUs) sont inclus dans le dossier `code/` (ex. `test_clean_df.py`) pour s'assurer que les transformations Spark s'exécutent avec succès. Les actions attendues sont notamment le filtrage des lignes trop courtes, le retrait de certains termes de copyright, et la restructuration des colonnes imbriquées.

## Licence

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

## Contact

Retrouvez-moi sur [LinkedIn](https://www.linkedin.com/in/n-jandot/)

_________________________________

# BigData EMR & AWS Fargate Project

This project illustrates the end-to-end deployment of a Big Data pipeline on AWS. It integrates the download of large datasets via AWS Fargate, their storage on Amazon S3, and their distributed processing with Apache Spark on an Amazon EMR cluster automatically provisioned by Terraform.

## Table of Contents
1. [Architecture](#architecture-1)
2. [Prerequisites](#prerequisites)
3. [Project Structure](#project-structure)
4. [Installation & Deployment](#installation--deployment)
5. [Usage](#usage-1)
6. [Tests](#tests-1)
7. [License](#license-1)
8. [Contact](#contact-1)

## Architecture

The data pipeline is organized into multiple stages (Medallion Architecture):

```mermaid
graph TD
    classDef source fill:#f9f,stroke:#333,stroke-width:2px;
    classDef compute fill:#f96,stroke:#333,stroke-width:2px;
    classDef storage fill:#6cf,stroke:#333,stroke-width:2px;
    classDef config fill:#ccc,stroke:#333,stroke-width:2px;

    %% Data Source
    Kaggle[("Kaggle Dataset<br>(The Pile - JSONL)")]:::source

    %% Ingestion
    Fargate["AWS Fargate<br>(Ingestion Container)"]:::compute

    %% Storage
    subgraph Data Lake S3
        S3Bronze[("S3 Bronze<br>(Raw JSONL)")]:::storage
        S3Gold[("S3 Gold<br>(Clean Parquet)")]:::storage
    end

    %% Processing
    EMR["Amazon EMR<br>(Apache Spark Job)"]:::compute

    %% IaC & Code
    TF["Terraform<br>(IaC Provisioning)"]:::config
    GH["GitHub Actions<br>(Code Sync)"]:::config

    %% Data Flow
    Kaggle -->|Download| Fargate
    Fargate -->|Upload Raw Data| S3Bronze
    S3Bronze -->|Read / Process| EMR
    EMR -->|Partitioned Save| S3Gold

    %% Infra Flow
    TF -.->|Provisions| EMR
    TF -.->|Configures| Data Lake S3
    GH -.->|Upload Scripts| Data Lake S3
```

1. **Ingestion (Fargate) -> Bronze (S3)**: A container running on AWS Fargate downloads an extract of *The Pile* dataset (~50GB) from Kaggle (JSONL format) and uploads it to S3. Fargate is preferred over Lambda due to the latter's processing time and resource limitations.
2. **Bronze -> Silver -> Gold (Spark on EMR)**: 
   - Data cleaning and conversion.
   - Text filtering and partitioning according to metadata.
   - The final data is stored on S3 in `.parquet` format, optimized and ready to be queried with Amazon Athena.
3. **Infrastructure as Code (Terraform)**: Creation of a secure VPC, public/private subnets, a Gateway Endpoint for S3, IAM/KMS roles and keys, and the EMR cluster.

## Prerequisites

- AWS CLI installed and configured
- AWS Credentials configured as secrets (ID and Role)
- Kaggle API key stored in AWS Systems Manager (SSM) parameters `/kaggle/username` and `/kaggle/key`
- Terraform `v1.x`
- Python `3.8+`
- Docker (for the Fargate image)

## Project Structure

- `code/`: PySpark transformation scripts (cleaning, transformation, partitioning). Also contains unit tests to validate the transformations.
- `fargate/`: Python script and Dockerfile to authenticate the Kaggle account, download the data, and send it to the "Bronze" S3 bucket.
- `terraform/`: IaC files defining the complete AWS infrastructure (Network, EMR, IAM, Security, etc.).
- `.github/workflows/`: GitHub Actions CI/CD pipeline to automate the creation of the S3 bucket, uploading execution scripts, and potentially deployment.

## Installation & Deployment

### 1. Fargate (Ingestion)

Build and push the Docker image containing the ingestion script to Amazon ECR:

```bash
# Create the ECR repository
aws ecr create-repository --repository-name emr-project

# Tag and push the image (replace aws_account_id and image_id)
docker tag <image_id> <aws_account_id>.dkr.ecr.eu-west-3.amazonaws.com/emr-project:latest
docker push <aws_account_id>.dkr.ecr.eu-west-3.amazonaws.com/emr-project:latest
```

### 2. Infrastructure (Terraform)

Ensure you have a pre-configured S3 bucket to store the Terraform state (if applicable) and scripts.

```bash
cd terraform
terraform init
# Import KMS key if it exists
terraform import aws_kms_key.emr <ARN-of-kms-key>
terraform apply -auto-approve
```

### 3. CI/CD

Using GitHub Actions (`main.yaml`) automates the creation of an S3 bucket (if it doesn't exist) and places the files from `code/` into it.

## Usage

The goal of this work is to end-to-end deploy a Spark script in an EMR (Elastic Map Reduce) cluster created by Terraform.
Once the infrastructure is built by Terraform, the EMR cluster initializes, downloads the scripts from S3, executes the PySpark job, and writes the transformed and partitioned results back to S3.

*Note: The Git branch history has been intentionally removed so as not to expose AWS credentials (although they are now externalized in secrets).*

## Tests

Unit tests are included in the `code/` folder (e.g., `test_clean_df.py`) to ensure the Spark transformations run successfully. Expected actions include filtering out short lines, removing certain copyright terms, and restructuring nested columns.

## License

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

## Contact

Find me on [LinkedIn](https://www.linkedin.com/in/n-jandot/)
