import Foundation
import SwiftUI

enum Framework: String, Codable, CaseIterable, Identifiable {
    // JavaScript/TypeScript Frameworks
    case nodejs = "Node.js"
    case angular = "Angular"
    case react = "React"
    case vue = "Vue"
    case nextjs = "Next.js"
    case express = "Express"
    case nestjs = "NestJS"
    
    // Python Frameworks
    case django = "Django"
    case flask = "Flask"
    case fastapi = "FastAPI"
    case purepy = "Python"
    
    // Rust
    case rust = "Rust"
    
    // Apple platforms
    case swift = "Swift"
    case swiftui = "SwiftUI"
    case objectiveC = "Objective-C"
    
    // Android
    case kotlin = "Kotlin"
    case jetpackCompose = "Jetpack Compose"
    case androidJava = "Java (Android)"
    
    // Cross-platform mobile
    case reactNative = "React Native"
    case flutter = "Flutter"
    
    // Go
    case go = "Go"
    
    // Java / JVM backend
    case java = "Java"
    case spring = "Spring"
    
    // Infrastructure
    case docker = "Docker"
    case kubernetes = "Kubernetes"
    case terraform = "Terraform"
    
    // Databases
    case postgresql = "PostgreSQL"
    case mysql = "MySQL"
    case mongodb = "MongoDB"
    case redis = "Redis"
    case sqlite = "SQLite"
    
    // File / object storage (Vault pod type)
    /// Pioneer-native file vault — local durable volume + simple index/API contract.
    case vault = "Vault"
    /// S3-compatible object storage (MinIO).
    case minio = "MinIO"
    /// AWS S3 (or S3-compatible remote bucket config).
    case s3 = "S3"
    /// Kubernetes / host local volume (PVC or hostPath).
    case localVolume = "Local Volume"
    /// Network File System share.
    case nfs = "NFS"
    /// Distributed object/file store (SeaweedFS).
    case seaweedfs = "SeaweedFS"
    
    /// Virtual Inference hub — `.env` + secret scopes (not a runtime language stack).
    case environment = "Environment"
    
    var id: String { rawValue }
    
    /// Settings UI grouping.
    var settingsCategory: String {
        switch self {
        case .nodejs, .angular, .react, .vue, .nextjs, .express, .nestjs, .reactNative:
            return "JavaScript / TypeScript"
        case .django, .flask, .fastapi, .purepy:
            return "Python"
        case .swift, .swiftui, .objectiveC:
            return "Apple (macOS / iOS)"
        case .kotlin, .jetpackCompose, .androidJava:
            return "Android"
        case .flutter:
            return "Cross-platform"
        case .rust, .go:
            return "Systems"
        case .java, .spring:
            return "Java / JVM"
        case .postgresql, .mysql, .mongodb, .redis, .sqlite:
            return "Database"
        case .vault, .minio, .s3, .localVolume, .nfs, .seaweedfs:
            return "Vault / Storage"
        case .docker, .kubernetes, .terraform:
            return "Infrastructure"
        case .environment:
            return "Inference"
        }
    }
    
    var icon: String {
        switch self {
        case .nodejs: return "server.rack"
        case .angular: return "a.circle"
        case .react: return "r.circle"
        case .vue: return "v.circle"
        case .nextjs: return "n.circle"
        case .express: return "e.circle"
        case .nestjs: return "n.square"
        case .django: return "d.circle"
        case .flask: return "f.circle"
        case .fastapi: return "bolt"
        case .purepy: return "chevron.left.forwardslash.chevron.right"
        case .rust: return "r.square"
        case .swift: return "swift"
        case .swiftui: return "swift"
        case .objectiveC: return "c.circle"
        case .kotlin: return "k.circle.fill"
        case .jetpackCompose: return "rectangle.3.group"
        case .androidJava: return "j.circle.fill"
        case .reactNative: return "iphone.gen3"
        case .flutter: return "bird"
        case .go: return "g.circle"
        case .java: return "j.circle"
        case .spring: return "leaf"
        case .docker: return "cube.box"
        case .kubernetes: return "circle.hexagongrid"
        case .terraform: return "mountain.2"
        case .postgresql: return "cylinder"
        case .mysql: return "cylinder.fill"
        case .mongodb: return "leaf.circle"
        case .redis: return "bolt.horizontal.circle"
        case .sqlite: return "internaldrive"
        case .vault: return "lock.rectangle.stack.fill"
        case .minio: return "cylinder.split.1x2.fill"
        case .s3: return "cloud.fill"
        case .localVolume: return "internaldrive.fill"
        case .nfs: return "network"
        case .seaweedfs: return "leaf.arrow.triangle.circlepath"
        case .environment: return "key.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .nodejs: return Color(red: 0.4, green: 0.7, blue: 0.3)
        case .angular: return Color(red: 0.9, green: 0.2, blue: 0.2)
        case .react: return Color(red: 0.2, green: 0.7, blue: 0.9)
        case .vue: return Color(red: 0.2, green: 0.7, blue: 0.4)
        case .nextjs: return Color.primary
        case .express: return Color.gray
        case .nestjs: return Color(red: 0.9, green: 0.2, blue: 0.2)
        case .django: return Color(red: 0.1, green: 0.4, blue: 0.2)
        case .flask: return Color.primary
        case .fastapi: return Color(red: 0.1, green: 0.6, blue: 0.4)
        case .purepy: return Color(red: 0.2, green: 0.6, blue: 0.9)
        case .rust: return Color(red: 0.7, green: 0.3, blue: 0.1)
        case .swift, .swiftui: return Color(red: 1.0, green: 0.58, blue: 0.0)
        case .objectiveC: return Color(red: 0.3, green: 0.5, blue: 0.9)
        case .kotlin: return Color(red: 0.5, green: 0.3, blue: 0.9)
        case .jetpackCompose: return Color(red: 0.2, green: 0.8, blue: 0.5)
        case .androidJava: return Color(red: 0.2, green: 0.7, blue: 0.3)
        case .reactNative: return Color(red: 0.3, green: 0.8, blue: 0.95)
        case .flutter: return Color(red: 0.2, green: 0.6, blue: 0.95)
        case .go: return Color(red: 0.0, green: 0.7, blue: 0.8)
        case .java: return Color(red: 0.9, green: 0.5, blue: 0.1)
        case .spring: return Color(red: 0.4, green: 0.7, blue: 0.3)
        case .docker: return Color(red: 0.1, green: 0.7, blue: 0.9)
        case .kubernetes: return Color(red: 0.3, green: 0.5, blue: 0.9)
        case .terraform: return Color(red: 0.6, green: 0.3, blue: 0.9)
        case .postgresql: return Color(red: 0.2, green: 0.4, blue: 0.7)
        case .mysql: return Color(red: 0.0, green: 0.45, blue: 0.65)
        case .mongodb: return Color(red: 0.3, green: 0.7, blue: 0.35)
        case .redis: return Color(red: 0.85, green: 0.2, blue: 0.2)
        case .sqlite: return Color(red: 0.1, green: 0.55, blue: 0.85)
        case .vault: return Color(red: 0.15, green: 0.55, blue: 0.65)
        case .minio: return Color(red: 0.85, green: 0.35, blue: 0.15)
        case .s3: return Color(red: 0.95, green: 0.55, blue: 0.15)
        case .localVolume: return Color(red: 0.35, green: 0.55, blue: 0.65)
        case .nfs: return Color(red: 0.25, green: 0.5, blue: 0.75)
        case .seaweedfs: return Color(red: 0.2, green: 0.7, blue: 0.45)
        case .environment: return Color(red: 0.55, green: 0.35, blue: 0.95)
        }
    }
    
    var primaryLanguage: CodeLanguage {
        switch self {
        case .nodejs, .angular, .react, .vue, .nextjs, .express, .nestjs, .reactNative:
            return .javascript
        case .django, .flask, .fastapi, .purepy:
            return .python
        case .rust, .go, .flutter, .environment, .vault, .minio, .s3, .localVolume, .nfs, .seaweedfs:
            return .bash
        case .swift, .swiftui:
            return .swift
        case .objectiveC:
            return .swift // closest highlighting
        case .java, .spring, .androidJava, .kotlin, .jetpackCompose:
            return .bash
        case .docker:
            return .dockerfile
        case .kubernetes:
            return .kubernetes
        case .terraform:
            return .terraform
        case .postgresql, .mysql, .sqlite:
            return .sql
        case .mongodb, .redis:
            return .bash
        }
    }
    
    var needsEnvironment: Bool {
        switch self {
        case .nodejs, .angular, .react, .vue, .nextjs, .express, .nestjs, .reactNative:
            return true
        case .django, .flask, .fastapi, .purepy:
            return true
        case .flutter:
            return true
        case .rust, .swift, .swiftui, .objectiveC, .go, .java, .spring,
             .kotlin, .jetpackCompose, .androidJava:
            return false
        case .docker, .kubernetes, .terraform, .environment:
            return false
        case .postgresql, .mysql, .mongodb, .redis, .sqlite:
            return false
        case .vault, .minio, .s3, .localVolume, .nfs, .seaweedfs:
            return false
        }
    }
    
    var launchFile: String {
        switch self {
        case .nodejs, .express:
            return "src/index.js"
        case .angular:
            return "src/main.ts"
        case .react:
            return "src/index.js"
        case .vue:
            return "src/main.js"
        case .nextjs:
            return "pages/index.js"
        case .nestjs:
            return "src/main.ts"
        case .django:
            return "manage.py"
        case .flask:
            return "app.py"
        case .fastapi:
            return "main.py"
        case .purepy:
            return "src/main.py"
        case .rust:
            return "src/main.rs"
        case .swift:
            return "Sources/main.swift"
        case .swiftui:
            return "Sources/App.swift"
        case .objectiveC:
            return "Sources/main.m"
        case .kotlin:
            return "app/src/main/java/com/example/app/MainActivity.kt"
        case .jetpackCompose:
            return "app/src/main/java/com/example/app/MainActivity.kt"
        case .androidJava:
            return "app/src/main/java/com/example/app/MainActivity.java"
        case .reactNative:
            return "App.js"
        case .flutter:
            return "lib/main.dart"
        case .go:
            return "main.go"
        case .java:
            return "src/main/java/Main.java"
        case .spring:
            return "src/main/java/Application.java"
        case .docker:
            return "Dockerfile"
        case .kubernetes:
            return "deployment.yaml"
        case .terraform:
            return "main.tf"
        case .postgresql:
            return "sql/init.sql"
        case .mysql:
            return "sql/init.sql"
        case .mongodb:
            return "scripts/init.js"
        case .redis:
            return "scripts/init.redis"
        case .sqlite:
            return "sql/schema.sql"
        case .vault:
            return "vault/README.md"
        case .minio:
            return "config/minio.env"
        case .s3:
            return "config/s3.env"
        case .localVolume:
            return "k8s/pvc.yaml"
        case .nfs:
            return "config/nfs.env"
        case .seaweedfs:
            return "config/seaweedfs.env"
        case .environment:
            return ".env"
        }
    }
    
    func getTemplate(name: String) -> String {
        switch self {
        case .nodejs:
            return """
            // \(name)
            // Node.js application entry point

            console.log('Hello, \(name)!');
            
            // Add your code here
            """
        case .angular:
            return """
            import { Component } from '@angular/core';

            @Component({
              selector: 'app-root',
              template: '<h1>Hello, \(name)!</h1>'
            })
            export class AppComponent {
              title = '\(name)';
            }
            """
        case .react:
            return """
            import React from 'react';

            function App() {
              return (
                <div>
                  <h1>Hello, \(name)!</h1>
                </div>
              );
            }

            export default App;
            """
        case .vue:
            return """
            <template>
              <div>
                <h1>Hello, \(name)!</h1>
              </div>
            </template>

            <script>
            export default {
              name: 'App'
            }
            </script>
            """
        case .nextjs:
            return """
            export default function Home() {
              return (
                <div>
                  <h1>Hello, \(name)!</h1>
                </div>
              );
            }
            """
        case .express:
            return """
            const express = require('express');
            const app = express();
            const port = 3000;

            app.get('/', (req, res) => {
              res.send('Hello, \(name)!');
            });

            app.listen(port, () => {
              console.log(`\(name) listening at http://localhost:${port}`);
            });
            """
        case .nestjs:
            return """
            import { Controller, Get } from '@nestjs/common';

            @Controller()
            export class AppController {
              @Get()
              getHello(): string {
                return 'Hello, \(name)!';
              }
            }
            """
        case .django:
            return """
            # \(name) Django Project
            # Django settings and configuration

            from django.http import HttpResponse

            def index(request):
                return HttpResponse("Hello, \(name)!")
            """
        case .flask:
            return """
            from flask import Flask

            app = Flask(__name__)

            @app.route('/')
            def hello():
                return 'Hello, \(name)!'

            if __name__ == '__main__':
                app.run(debug=True)
            """
        case .fastapi:
            return """
            from fastapi import FastAPI

            app = FastAPI(title="\(name)")

            @app.get("/")
            def read_root():
                return {"message": "Hello, \(name)!"}
            """
        case .purepy:
            return """
            # \(name)
            # Pure Python application

            def main():
                print("Hello, \(name)!")

            if __name__ == "__main__":
                main()
            """
        case .rust:
            return """
            fn main() {
                println!("Hello, \(name)!");
            }
            """
        case .swift:
            return """
            import Foundation

            print("Hello, \(name)!")
            """
        case .swiftui:
            return """
            import SwiftUI

            @main
            struct \(name.replacingOccurrences(of: " ", with: ""))App: App {
                var body: some Scene {
                    WindowGroup {
                        ContentView()
                    }
                }
            }

            struct ContentView: View {
                var body: some View {
                    Text("Hello, \(name)!")
                        .font(.largeTitle)
                        .padding()
                }
            }
            """
        case .objectiveC:
            return """
            #import <Foundation/Foundation.h>

            int main(int argc, const char * argv[]) {
                @autoreleasepool {
                    NSLog(@"Hello, \(name)!");
                }
                return 0;
            }
            """
        case .kotlin:
            return """
            package com.example.app

            import android.os.Bundle
            import android.widget.TextView
            import androidx.appcompat.app.AppCompatActivity

            class MainActivity : AppCompatActivity() {
                override fun onCreate(savedInstanceState: Bundle?) {
                    super.onCreate(savedInstanceState)
                    val text = TextView(this).apply {
                        text = "Hello, \(name)!"
                        textSize = 24f
                    }
                    setContentView(text)
                }
            }
            """
        case .jetpackCompose:
            return """
            package com.example.app

            import android.os.Bundle
            import androidx.activity.ComponentActivity
            import androidx.activity.compose.setContent
            import androidx.compose.material3.Text
            import androidx.compose.runtime.Composable
            import androidx.compose.ui.tooling.preview.Preview

            class MainActivity : ComponentActivity() {
                override fun onCreate(savedInstanceState: Bundle?) {
                    super.onCreate(savedInstanceState)
                    setContent {
                        Greeting(name = "\(name)")
                    }
                }
            }

            @Composable
            fun Greeting(name: String) {
                Text(text = "Hello, $name!")
            }

            @Preview
            @Composable
            fun PreviewGreeting() {
                Greeting("\(name)")
            }
            """
        case .androidJava:
            return """
            package com.example.app;

            import android.os.Bundle;
            import android.widget.TextView;
            import androidx.appcompat.app.AppCompatActivity;

            public class MainActivity extends AppCompatActivity {
                @Override
                protected void onCreate(Bundle savedInstanceState) {
                    super.onCreate(savedInstanceState);
                    TextView text = new TextView(this);
                    text.setText("Hello, \(name)!");
                    text.setTextSize(24);
                    setContentView(text);
                }
            }
            """
        case .reactNative:
            return """
            import React from 'react';
            import { SafeAreaView, Text, StyleSheet } from 'react-native';

            export default function App() {
              return (
                <SafeAreaView style={styles.container}>
                  <Text style={styles.title}>Hello, \(name)!</Text>
                </SafeAreaView>
              );
            }

            const styles = StyleSheet.create({
              container: { flex: 1, alignItems: 'center', justifyContent: 'center' },
              title: { fontSize: 24, fontWeight: '600' },
            });
            """
        case .flutter:
            return """
            import 'package:flutter/material.dart';

            void main() {
              runApp(const MyApp());
            }

            class MyApp extends StatelessWidget {
              const MyApp({super.key});

              @override
              Widget build(BuildContext context) {
                return MaterialApp(
                  title: '\(name)',
                  home: Scaffold(
                    appBar: AppBar(title: const Text('\(name)')),
                    body: const Center(
                      child: Text('Hello, \(name)!'),
                    ),
                  ),
                );
              }
            }
            """
        case .go:
            return """
            package main

            import "fmt"

            func main() {
                fmt.Println("Hello, \(name)!")
            }
            """
        case .java:
            return """
            public class Main {
                public static void main(String[] args) {
                    System.out.println("Hello, \(name)!");
                }
            }
            """
        case .spring:
            return """
            package com.example;

            import org.springframework.boot.SpringApplication;
            import org.springframework.boot.autoconfigure.SpringBootApplication;

            @SpringBootApplication
            public class Application {
                public static void main(String[] args) {
                    SpringApplication.run(Application.class, args);
                }
            }
            """
        case .docker:
            return """
            FROM node:20-alpine
            WORKDIR /app
            COPY package*.json ./
            RUN npm install
            COPY . .
            EXPOSE 3000
            CMD ["npm", "start"]
            """
        case .kubernetes:
            return """
            apiVersion: apps/v1
            kind: Deployment
            metadata:
              name: \(name.lowercased())
            spec:
              replicas: 1
              selector:
                matchLabels:
                  app: \(name.lowercased())
              template:
                metadata:
                  labels:
                    app: \(name.lowercased())
                spec:
                  containers:
                  - name: app
                    image: \(name.lowercased()):latest
                    ports:
                    - containerPort: 3000
            """
        case .terraform:
            return """
            terraform {
              required_version = ">= 1.0"
            }

            resource "aws_instance" "example" {
              ami           = "ami-0c55b159cbfafe1f0"
              instance_type = "t2.micro"

              tags = {
                Name = "\(name)"
              }
            }
            """
        case .postgresql:
            return """
            -- \(name) · PostgreSQL schema
            -- Applied on first start via /docker-entrypoint-initdb.d

            CREATE TABLE IF NOT EXISTS items (
                id          BIGSERIAL PRIMARY KEY,
                name        TEXT NOT NULL,
                created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
            );

            INSERT INTO items (name) VALUES ('Hello, \(name)!')
            ON CONFLICT DO NOTHING;
            """
        case .mysql:
            return """
            -- \(name) · MySQL schema

            CREATE TABLE IF NOT EXISTS items (
                id          BIGINT AUTO_INCREMENT PRIMARY KEY,
                name        VARCHAR(255) NOT NULL,
                created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
            );

            INSERT INTO items (name) VALUES ('Hello, \(name)!');
            """
        case .mongodb:
            return """
            // \(name) · MongoDB init script
            // Run with: mongosh < scripts/init.js

            db = db.getSiblingDB('app');
            db.items.insertOne({
              name: 'Hello, \(name)!',
              createdAt: new Date()
            });
            print('Seeded \(name)');
            """
        case .redis:
            return """
            # \(name) · Redis seed commands
            # redis-cli < scripts/init.redis

            SET app:greeting "Hello, \(name)!"
            SADD app:tags pioneer database redis
            """
        case .sqlite:
            return """
            -- \(name) · SQLite schema

            CREATE TABLE IF NOT EXISTS items (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                name        TEXT NOT NULL,
                created_at  TEXT NOT NULL DEFAULT (datetime('now'))
            );

            INSERT INTO items (name) VALUES ('Hello, \(name)!');
            """
        case .vault:
            return """
            # \(name) — Pioneer Vault
            #
            # Durable file storage for the stack. Mount `./data` (or PVC) as the vault root.
            # Other pods read/write objects under this volume via path or S3-compatible API.

            ## Layout
            ```
            data/
              buckets/
                public/     # non-secret assets
                private/    # access-controlled
                uploads/    # client uploads
              index.json    # optional object index
            ```

            ## Contract
            - Root: `/vault` in containers (bind-mount from host `./data`)
            - Paths are namespaced by bucket: `/vault/buckets/<bucket>/<key>`
            - Prefer content-addressable keys for large blobs: `sha256/<hash>`

            ## Quick start
            ```bash
            mkdir -p data/buckets/{public,private,uploads}
            echo '{"version":1,"buckets":["public","private","uploads"]}' > data/index.json
            ```

            Wire this Vault pod to services that need uploads, media, or model artifacts.
            """
        case .minio:
            return """
            # \(name) — MinIO (S3-compatible)
            MINIO_ROOT_USER=minioadmin
            MINIO_ROOT_PASSWORD=minioadmin
            MINIO_VOLUMES=/data
            MINIO_ADDRESS=:9000
            MINIO_CONSOLE_ADDRESS=:9001

            # Client endpoint for other pods
            S3_ENDPOINT=http://minio:9000
            S3_BUCKET=app
            S3_ACCESS_KEY=minioadmin
            S3_SECRET_KEY=minioadmin
            S3_REGION=us-east-1
            S3_USE_SSL=false
            """
        case .s3:
            return """
            # \(name) — AWS S3 / S3-compatible remote
            AWS_REGION=us-east-1
            AWS_ACCESS_KEY_ID=
            AWS_SECRET_ACCESS_KEY=
            S3_BUCKET=\(name.lowercased().replacingOccurrences(of: " ", with: "-"))
            S3_ENDPOINT=
            # Leave S3_ENDPOINT empty for real AWS; set for R2/Wasabi/etc.
            S3_PREFIX=app/
            S3_USE_SSL=true
            """
        case .localVolume:
            return """
            # \(name) — Local Volume / PVC
            # Apply with: kubectl apply -f k8s/pvc.yaml
            #
            # This file is a note; real PVC YAML is generated in the pod YAML view.
            VAULT_MOUNT_PATH=/vault
            VAULT_SIZE=10Gi
            VAULT_STORAGE_CLASS=standard
            VAULT_ACCESS_MODE=ReadWriteOnce
            """
        case .nfs:
            return """
            # \(name) — NFS share
            NFS_SERVER=nfs.local
            NFS_PATH=/exports/pioneer
            NFS_MOUNT_OPTIONS=rw,nolock,soft
            VAULT_MOUNT_PATH=/vault
            """
        case .seaweedfs:
            return """
            # \(name) — SeaweedFS
            SEAWEED_MASTER=:9333
            SEAWEED_VOLUME=:8080
            SEAWEED_FILER=:8888
            SEAWEED_S3=:8333
            # Filer root for app files
            SEAWEED_DIR=/buckets/app
            """
        case .environment:
            return """
            # \(name) — Inference environment
            API_BASE_URL=http://localhost:8000
            DATABASE_URL=mysql://user:pass@db:3306/app
            JWT_SECRET=change-me
            API_PUBLIC_KEY=
            API_PRIVATE_KEY=
            DEBUG=true
            """
        }
    }
}

