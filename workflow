name: 🚀 Déclenchement Manuel (CI/CD)

on:
  workflow_dispatch:
    # --- DÉFINITION DU FORMULAIRE ---
    inputs:
      # Étapes de base
      run_build:
        description: '✅ 1. Lancer le Build'
        required: true
        type: boolean
        default: true
      run_tests:
        description: '🧪 2. Lancer les Tests Unitaires/Intégration'
        required: true
        type: boolean
        default: true
      run_analysis:
        description: 'Sonar 3. Lancer l-analyse SonarQube'
        required: true
        type: boolean
        default: true
      
      # Gating et Déploiement
      run_gating:
        description: '✋ 4. Appliquer le Quality Gate (faire échouer le pipeline si la qualité Sonar est insuffisante)'
        required: true
        type: boolean
        default: true
      run_deploy:
        description: '📦 5. Lancer le Déploiement'
        required: true
        type: boolean
        default: false # Action sensible, désactivée par défaut

      # Options de déploiement (s-affichent si "run_deploy" est coché)
      deploy_env:
        description: '  Environnement de déploiement'
        required: false # Pas requis si run_deploy est false
        type: choice
        options:
        - staging
        - production
        default: 'staging'

      # Release
      run_release:
        description: '🎉 6. Créer une Release GitHub'
        required: true
        type: boolean
        default: false # Action sensible, désactivée par défaut
      release_tag:
        description: '  Tag pour la release (ex: v1.0.1)'
        required: false
        type: string

jobs:
  # -----------------------------------------------------------------
  # JOB 1: BUILD
  # -----------------------------------------------------------------
  build:
    name: '1. Build'
    # Condition : Ne s'exécute que si la case "run_build" est cochée
    if: github.event.inputs.run_build == 'true'
    runs-on: ubuntu-latest
    
    outputs:
      build_success: true # Permet aux autres jobs de savoir que le build a réussi

    steps:
      - name: Checkout du code
        uses: actions/checkout@v4
      
      - name: ☕ Setup Java (ou Node, Python, etc.)
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
          cache: 'maven'

      - name: 🚀 Lancer le build (ex: Maven)
        run: mvn -B package -DskipTests # On build seulement, -DskipTests est courant ici
      
      # Vous devriez sauvegarder vos artéfacts pour les jobs suivants
      - name: Sauvegarder l-artéfact (ex: .jar)
        uses: actions/upload-artifact@v4
        with:
          name: mon-application
          path: target/*.jar

  # -----------------------------------------------------------------
  # JOB 2: TESTS
  # -----------------------------------------------------------------
  test:
    name: '2. Tests'
    needs: build # Dépend du succès du job 'build'
    # Condition : Si la case "run_tests" est cochée
    if: github.event.inputs.run_tests == 'true'
    runs-on: ubuntu-latest

    steps:
      - name: Checkout du code
        uses: actions/checkout@v4
        
      - name: ☕ Setup Java
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
          cache: 'maven'
          
      # Pas besoin de re-télécharger les dépendances si le cache est bon
      # Mais on doit télécharger l'artéfact si les tests sont d'intégration
      - name: Télécharger l-artéfact (si nécessaire)
        uses: actions/download-artifact@v4
        with:
          name: mon-application
          path: target/
          
      - name: 🧪 Lancer les tests (ex: Maven)
        run: mvn -B test
        
      # Sauvegarder les rapports de tests/couverture pour Sonar
      - name: Sauvegarder les rapports de tests
        uses: actions/upload-artifact@v4
        with:
          name: test-reports
          path: |
            target/surefire-reports/
            target/jacoco.exec
          retention-days: 1 # On n'a besoin de ces rapports que temporairement

  # -----------------------------------------------------------------
  # JOB 3: ANALYSE SONAR
  # -----------------------------------------------------------------
  analyze:
    name: '3. Analyse Sonar & Quality Gate'
    # Dépend du build et des tests (pour les rapports de couverture)
    needs: [build, test]
    # Condition : Si "run_analysis" est coché ET si les jobs précédents ont réussi OU ont été sautés
    if: >
      github.event.inputs.run_analysis == 'true' &&
      (needs.build.result == 'success' || needs.build.result == 'skipped') &&
      (needs.test.result == 'success' || needs.test.result == 'skipped')
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout du code (avec historique complet)
        uses: actions/checkout@v4
        with:
          fetch-depth: 0 # Nécessaire pour SonarQube

      - name: ☕ Setup Java
        uses: actions/setup-java@v4
        with:
          java-version: '17'
          distribution: 'temurin'
          cache: 'maven'
          
      - name: Télécharger les rapports de tests
        uses: actions/download-artifact@v4
        with:
          name: test-reports
          path: target/
      
      - name: 🏃 Lancer l-analyse Sonar
        env:
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          # Variable pour le Quality Gate
          WAIT_FOR_GATE="false"
          if [ "${{ github.event.inputs.run_gating }}" == "true" ]; then
            WAIT_FOR_GATE="true"
          fi
          
          echo "Quality Gate attendra: $WAIT_FOR_GATE"

          # La commande 'verify' re-exécute les tests pour générer les rapports
          # que Sonar utilise.
          mvn -B verify sonar:sonar \
            -Dsonar.projectKey=VOTRE_PROJET_SONAR \
            -Dsonar.host.url=https://VOTRE_INSTANCE_SONAR.COM \
            -Dsonar.token=${{ env.SONAR_TOKEN }} \
            -Dsonar.qualitygate.wait=$WAIT_FOR_GATE
            
  # -----------------------------------------------------------------
  # JOB 4: DÉPLOIEMENT
  # -----------------------------------------------------------------
  deploy:
    name: '📦 5. Déploiement vers ${{ github.event.inputs.deploy_env }}'
    # Dépend de toutes les étapes de qualité
    needs: [build, test, analyze]
    # Condition : Si "run_deploy" est coché ET si tous les jobs précédents ont réussi OU ont été sautés
    if: >
      github.event.inputs.run_deploy == 'true' &&
      (needs.build.result == 'success') &&
      (needs.test.result == 'success' || needs.test.result == 'skipped') &&
      (needs.analyze.result == 'success' || needs.analyze.result == 'skipped')
    runs-on: ubuntu-latest
    
    # Utilise les Environnements GitHub pour les secrets et les règles de protection
    environment:
      name: ${{ github.event.inputs.deploy_env }}
      url: https://mon-app.${{ github.event.inputs.deploy_env }}.com # URL dynamique (optionnel)

    steps:
      - name: Télécharger l-artéfact
        uses: actions/download-artifact@v4
        with:
          name: mon-application
          path: .
          
      - name: 'Affichage de l-artéfact (simulation)'
        run: ls -l
        
      - name: '🚀 Déployer (ex: vers AWS S3, Azure, Heroku...)'
        run: |
          echo "Déploiement de l'artéfact vers ${{ github.event.inputs.deploy_env }}..."
          # Ex: aws s3 sync . s3://${{ secrets.S3_BUCKET }}/${{ github.event.inputs.deploy_env }}/
          sleep 10 # Simule une action de déploiement
          echo "Déploiement terminé."
        # Les secrets (ex: AWS_ACCESS_KEY_ID) sont souvent liés à l'environnement GitHub
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

  # -----------------------------------------------------------------
  # JOB 5: RELEASE
  # -----------------------------------------------------------------
  release:
    name: '🎉 6. Créer une Release GitHub'
    needs: deploy # Ne crée la release que si le déploiement a réussi
    # Condition : Si "run_release" est coché ET si le tag est fourni
    if: >
      github.event.inputs.run_release == 'true' &&
      github.event.inputs.release_tag != ''
    runs-on: ubuntu-latest
    permissions:
      contents: write # Nécessaire pour créer une release

    steps:
      - name: Télécharger l-artéfact (pour l-attacher à la release)
        uses: actions/download-artifact@v4
        with:
          name: mon-application
          path: .

      - name: 🏷️ Créer la Release GitHub
        uses: actions/create-release@v1
        with:
          tag_name: ${{ github.event.inputs.release_tag }}
          release_name: 'Release ${{ github.event.inputs.release_tag }}'
          body: |
            Release automatique déployée sur ${{ github.event.inputs.deploy_env }}.
          draft: false
          prerelease: false
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          
      - name: 📎 Attacher l-artéfact à la release (exemple)
        uses: actions/upload-release-asset@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          upload_url: ${{ steps.create_release.outputs.upload_url }} # URL de l'étape précédente
          asset_path: ./mon-application.jar # Nom de votre artéfact
          asset_name: mon-application-${{ github.event.inputs.release_tag }}.jar
          asset_content_type: application/java-archive
