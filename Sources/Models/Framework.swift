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
    case purepy = "PurePy"
    
    // Rust
    case rust = "Rust"
    
    // Swift
    case swift = "Swift"
    case swiftui = "SwiftUI"
    
    // Go
    case go = "Go"
    
    // Java
    case java = "Java"
    case spring = "Spring"
    
    // Infrastructure
    case docker = "Docker"
    case kubernetes = "Kubernetes"
    case terraform = "Terraform"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .nodejs: return "nodejs"
        case .angular: return "a.circle"
        case .react: return "r.circle"
        case .vue: return "v.circle"
        case .nextjs: return "n.circle"
        case .express: return "e.circle"
        case .nestjs: return "n.square"
        case .django: return "d.circle"
        case .flask: return "f.circle"
        case .fastapi: return "bolt"
        case .purepy: return "python"
        case .rust: return "r.square"
        case .swift: return "swift"
        case .swiftui: return "swift"
        case .go: return "g.circle"
        case .java: return "j.circle"
        case .spring: return "s.circle"
        case .docker: return "cube.box"
        case .kubernetes: return "k.circle"
        case .terraform: return "mountain.2"
        }
    }
    
    var color: Color {
        switch self {
        case .nodejs: return Color(red: 0.4, green: 0.7, blue: 0.3) // Green
        case .angular: return Color(red: 0.9, green: 0.2, blue: 0.2) // Red
        case .react: return Color(red: 0.2, green: 0.7, blue: 0.9) // Cyan
        case .vue: return Color(red: 0.2, green: 0.7, blue: 0.4) // Green
        case .nextjs: return Color.black
        case .express: return Color.gray
        case .nestjs: return Color(red: 0.9, green: 0.2, blue: 0.2) // Red
        case .django: return Color(red: 0.1, green: 0.4, blue: 0.2) // Dark Green
        case .flask: return Color.black
        case .fastapi: return Color(red: 0.1, green: 0.6, blue: 0.4) // Teal
        case .purepy: return Color(red: 0.2, green: 0.6, blue: 0.9) // Blue
        case .rust: return Color(red: 0.7, green: 0.3, blue: 0.1) // Orange
        case .swift: return Color(red: 1.0, green: 0.58, blue: 0.0) // Orange
        case .swiftui: return Color(red: 1.0, green: 0.58, blue: 0.0) // Orange
        case .go: return Color(red: 0.0, green: 0.7, blue: 0.8) // Cyan
        case .java: return Color(red: 0.9, green: 0.5, blue: 0.1) // Orange
        case .spring: return Color(red: 0.4, green: 0.7, blue: 0.3) // Green
        case .docker: return Color(red: 0.1, green: 0.7, blue: 0.9) // Cyan
        case .kubernetes: return Color(red: 0.3, green: 0.5, blue: 0.9) // Blue
        case .terraform: return Color(red: 0.6, green: 0.3, blue: 0.9) // Purple
        }
    }
    
    var primaryLanguage: CodeLanguage {
        switch self {
        case .nodejs, .angular, .react, .vue, .nextjs, .express, .nestjs:
            return .javascript
        case .django, .flask, .fastapi, .purepy:
            return .python
        case .rust:
            return .bash // Will need Rust syntax highlighting
        case .swift, .swiftui:
            return .swift
        case .go:
            return .bash // Will need Go syntax highlighting
        case .java, .spring:
            return .bash // Will need Java syntax highlighting
        case .docker:
            return .dockerfile
        case .kubernetes:
            return .kubernetes
        case .terraform:
            return .terraform
        }
    }
    
    var needsEnvironment: Bool {
        switch self {
        case .nodejs, .angular, .react, .vue, .nextjs, .express, .nestjs:
            return true // Needs Volta/Node.js
        case .django, .flask, .fastapi, .purepy:
            return true // Needs Python venv
        case .rust, .swift, .swiftui, .go, .java, .spring:
            return false // Compiled languages
        case .docker, .kubernetes, .terraform:
            return false // Infrastructure
        }
    }
    
    var launchFile: String {
        switch self {
        case .nodejs:
            return "src/index.js"
        case .angular:
            return "src/main.ts"
        case .react:
            return "src/index.js"
        case .vue:
            return "src/main.js"
        case .nextjs:
            return "pages/index.js"
        case .express:
            return "src/index.js"
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
        }
    }
}

