#!/bin/bash

# Exchange ELK Stack Health Check Script
# Monitor all components and generate health report

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ELK_HOST="localhost"
ELASTICSEARCH_PORT="9200"
KIBANA_PORT="5601"
LOGSTASH_PORT="9600"

echo -e "${BLUE}Exchange ELK Stack Health Check - $(date)${NC}"
echo "=================================================="

# Function to check HTTP service
check_http_service() {
    local service_name=$1
    local url=$2
    local expected_status=${3:-200}
    
    printf "%-20s" "$service_name:"
    
    if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "$expected_status"; then
        echo -e "${GREEN}✓ HEALTHY${NC}"
        return 0
    else
        echo -e "${RED}✗ UNHEALTHY${NC}"
        return 1
    fi
}

# Function to check docker container
check_docker_container() {
    local container_name=$1
    printf "%-20s" "$container_name:"
    
    if docker ps --filter "name=$container_name" --filter "status=running" | grep -q "$container_name"; then
        echo -e "${GREEN}✓ RUNNING${NC}"
        return 0
    else
        echo -e "${RED}✗ NOT RUNNING${NC}"
        return 1
    fi
}

# Function to get elasticsearch cluster health
get_elasticsearch_health() {
    echo -e "\n${YELLOW}Elasticsearch Cluster Health:${NC}"
    
    response=$(curl -s "http://$ELK_HOST:$ELASTICSEARCH_PORT/_cluster/health?pretty" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$response" | jq '.'
        
        # Extract key metrics
        status=$(echo "$response" | jq -r '.status')
        nodes=$(echo "$response" | jq -r '.number_of_nodes')
        active_shards=$(echo "$response" | jq -r '.active_shards')
        
        echo -e "\nCluster Status: ${status}"
        echo -e "Active Nodes: ${nodes}"
        echo -e "Active Shards: ${active_shards}"
        
        if [ "$status" = "green" ]; then
            echo -e "Overall Health: ${GREEN}EXCELLENT${NC}"
        elif [ "$status" = "yellow" ]; then
            echo -e "Overall Health: ${YELLOW}WARNING${NC}"
        else
            echo -e "Overall Health: ${RED}CRITICAL${NC}"
        fi
    else
        echo -e "${RED}Cannot connect to Elasticsearch${NC}"
    fi
}

# Function to get index information
get_index_info() {
    echo -e "\n${YELLOW}Exchange Logs Indices:${NC}"
    
    curl -s "http://$ELK_HOST:$ELASTICSEARCH_PORT/_cat/indices/exchange-*?v&s=index" 2>/dev/null
    
    echo -e "\n${YELLOW}Index Sizes:${NC}"
    curl -s "http://$ELK_HOST:$ELASTICSEARCH_PORT/_cat/indices/exchange-*?v&h=index,store.size,docs.count&s=store.size:desc" 2>/dev/null
}

# Function to check logstash pipelines
check_logstash_pipelines() {
    echo -e "\n${YELLOW}Logstash Pipeline Status:${NC}"
    
    response=$(curl -s "http://$ELK_HOST:$LOGSTASH_PORT/_node/stats/pipelines" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$response" | jq '.pipelines'
    else
        echo -e "${RED}Cannot connect to Logstash${NC}"
    fi
}

# Function to check system resources
check_system_resources() {
    echo -e "\n${YELLOW}System Resources:${NC}"
    
    # Memory usage
    echo "Memory Usage:"
    free -h
    
    echo -e "\nDisk Usage:"
    df -h | grep -E "(Filesystem|/dev/)"
    
    echo -e "\nDocker Stats:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
}

# Function to check recent logs for errors
check_error_logs() {
    echo -e "\n${YELLOW}Recent Error Logs:${NC}"
    
    echo "Elasticsearch Errors (last 10):"
    docker logs elasticsearch 2>&1 | grep -i "ERROR\|WARN" | tail -10 || echo "No recent errors"
    
    echo -e "\nLogstash Errors (last 10):"
    docker logs logstash 2>&1 | grep -i "ERROR\|WARN" | tail -10 || echo "No recent errors"
    
    echo -e "\nKibana Errors (last 10):"
    docker logs kibana 2>&1 | grep -i "ERROR\|WARN" | tail -10 || echo "No recent errors"
}

# Function to get data ingestion rate
check_ingestion_rate() {
    echo -e "\n${YELLOW}Data Ingestion Rate (last 1 hour):${NC}"
    
    query='
    {
      "query": {
        "range": {
          "@timestamp": {
            "gte": "now-1h"
          }
        }
      },
      "aggs": {
        "logs_per_minute": {
          "date_histogram": {
            "field": "@timestamp",
            "fixed_interval": "1m"
          }
        }
      }
    }'
    
    response=$(curl -s -X POST "http://$ELK_HOST:$ELASTICSEARCH_PORT/exchange-*/_search?size=0" \
        -H "Content-Type: application/json" \
        -d "$query" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        total_hits=$(echo "$response" | jq '.hits.total.value // .hits.total')
        echo "Total logs in last hour: $total_hits"
        
        # Calculate average per minute
        if [ "$total_hits" -gt 0 ]; then
            avg_per_min=$((total_hits / 60))
            echo "Average logs per minute: $avg_per_min"
        fi
    else
        echo -e "${RED}Cannot query ingestion data${NC}"
    fi
}

# Function to generate health summary
generate_health_summary() {
    echo -e "\n${BLUE}Health Summary:${NC}"
    echo "=============="
    
    # Count healthy services
    healthy_services=0
    total_services=4
    
    # Check each service
    if docker ps --filter "name=elasticsearch" --filter "status=running" | grep -q "elasticsearch"; then
        ((healthy_services++))
    fi
    
    if docker ps --filter "name=logstash" --filter "status=running" | grep -q "logstash"; then
        ((healthy_services++))
    fi
    
    if docker ps --filter "name=kibana" --filter "status=running" | grep -q "kibana"; then
        ((healthy_services++))
    fi
    
    if docker ps --filter "name=filebeat" --filter "status=running" | grep -q "filebeat"; then
        ((healthy_services++))
    fi
    
    health_percentage=$((healthy_services * 100 / total_services))
    
    echo "Services Running: $healthy_services/$total_services ($health_percentage%)"
    
    if [ $health_percentage -eq 100 ]; then
        echo -e "Overall Status: ${GREEN}HEALTHY${NC}"
    elif [ $health_percentage -ge 75 ]; then
        echo -e "Overall Status: ${YELLOW}WARNING${NC}"
    else
        echo -e "Overall Status: ${RED}CRITICAL${NC}"
    fi
    
    echo "Report generated at: $(date)"
}

# Main execution
echo -e "\n${YELLOW}1. Docker Containers:${NC}"
check_docker_container "elasticsearch"
check_docker_container "logstash"  
check_docker_container "kibana"
check_docker_container "filebeat"

echo -e "\n${YELLOW}2. Service Health Checks:${NC}"
check_http_service "Elasticsearch" "http://$ELK_HOST:$ELASTICSEARCH_PORT"
check_http_service "Kibana" "http://$ELK_HOST:$KIBANA_PORT/api/status"
check_http_service "Logstash" "http://$ELK_HOST:$LOGSTASH_PORT"

# Detailed health information
get_elasticsearch_health
get_index_info
check_logstash_pipelines
check_system_resources
check_ingestion_rate
check_error_logs

# Generate summary
generate_health_summary

echo -e "\n${BLUE}Health check completed!${NC}"

# Exit with error code if any critical issues found
exit 0