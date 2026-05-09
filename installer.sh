#!/bin/bash
set -e

# ============================================================
#  SimpleX Server Installer
#  SMP + XFTP + TURN (coturn)
#  https://github.com/ntorgov/simplex_bundle
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

INSTALL_DIR="$HOME/simplex"

print_banner() {
  echo -e "${CYAN}"
  echo '  ____  _                 _     __  __'
  echo ' / ___|(_)_ __ ___  _ __| | ___\ \/ /'
  echo ' \___ \| | '"'"'_ ` _ \| '"'"'_ \ |/ _ \\  / '
  echo '  ___) | | | | | | | |_) | |  __//  \ '
  echo ' |____/|_|_| |_| |_| .__/|_|\___/_/\_\'
  echo '                    |_|                '
  echo -e "${NC}"
  echo -e "${BOLD}  Self-hosted Server Installer${NC}"
  echo -e "${DIM}  SMP • XFTP • TURN${NC}"
  echo ""
}

print_step() {
  echo -e "\n${BLUE}${BOLD}[$1]${NC} ${BOLD}$2${NC}"
}

print_ok() {
  echo -e "  ${GREEN}✓${NC} $1"
}

print_warn() {
  echo -e "  ${YELLOW}⚠${NC}  $1"
}

print_error() {
  echo -e "  ${RED}✗${NC} $1"
}

print_info() {
  echo -e "  ${DIM}→${NC} $1"
}

# ── Проверка зависимостей ──────────────────────────────────

check_deps() {
  print_step "1/5" "Проверка зависимостей"

  local missing=()
  local compose_mode=""

  if ! command -v docker &>/dev/null; then
    missing+=("docker")
  else
    print_ok "Docker найден: $(docker --version | cut -d' ' -f3 | tr -d ',')"
  fi

  if command -v docker-compose &>/dev/null; then
    compose_mode="standalone"
    print_ok "docker-compose найден"
  elif docker compose version &>/dev/null 2>&1; then
    compose_mode="plugin"
    print_ok "docker compose (plugin) найден"
  else
    missing+=("docker-compose")
  fi

  if ! command -v openssl &>/dev/null; then
    missing+=("openssl")
  else
    print_ok "openssl найден"
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    echo ""
    print_error "Не хватает: ${missing[*]}"
    echo ""
    echo -e "  Установите Docker: ${CYAN}https://docs.docker.com/engine/install/${NC}"
    exit 1
  fi

  # Проверяем доступ к Docker API. Если сокет недоступен, используем sudo.
  if docker info &>/dev/null; then
    DOCKER_CMD=(docker)
    if [ "$compose_mode" = "standalone" ]; then
      COMPOSE_CMD=(docker-compose)
    else
      COMPOSE_CMD=(docker compose)
    fi
  else
    if ! command -v sudo &>/dev/null; then
      print_error "Нет доступа к Docker API и sudo не найден"
      print_info "Добавьте пользователя в группу docker или запустите скрипт от root"
      exit 1
    fi

    print_warn "Нет доступа к /var/run/docker.sock, команды Docker будут выполнены через sudo"
    DOCKER_CMD=(sudo docker)
    if [ "$compose_mode" = "standalone" ]; then
      COMPOSE_CMD=(sudo docker-compose)
    else
      COMPOSE_CMD=(sudo docker compose)
    fi
  fi
}

# ── Сбор параметров ────────────────────────────────────────

collect_params() {
  print_step "2/5" "Настройка параметров"
  echo ""

  local input_source="/dev/stdin"
  if [ -r /dev/tty ]; then
    input_source="/dev/tty"
  fi

  # Адрес сервера
  local default_addr=""
  if command -v hostname &>/dev/null; then
    default_addr=$(hostname -f 2>/dev/null || true)
  fi

  while true; do
    if [ -n "$default_addr" ]; then
      echo -en "  ${BOLD}Адрес сервера${NC} ${DIM}(домен или IP)${NC} [${default_addr}]: "
    else
      echo -en "  ${BOLD}Адрес сервера${NC} ${DIM}(домен или IP)${NC}: "
    fi
    read -r SERVER_ADDR < "$input_source"
    SERVER_ADDR="${SERVER_ADDR:-$default_addr}"
    [ -n "$SERVER_ADDR" ] && break
    print_warn "Адрес не может быть пустым"
  done

  # Порт SMP
  echo -en "  ${BOLD}Порт SMP${NC} ${DIM}(relay, рекомендуем 993 для обхода блокировок)${NC} [993]: "
  read -r SMP_PORT < "$input_source"
  SMP_PORT="${SMP_PORT:-993}"

  # Порт XFTP
  echo -en "  ${BOLD}Порт XFTP${NC} ${DIM}(файлы, рекомендуем 995)${NC} [995]: "
  read -r XFTP_PORT < "$input_source"
  XFTP_PORT="${XFTP_PORT:-995}"

  # Порт TURN
  echo -en "  ${BOLD}Порт TURN${NC} ${DIM}(голосовые звонки)${NC} [3478]: "
  read -r TURN_PORT < "$input_source"
  TURN_PORT="${TURN_PORT:-3478}"

  # Квота XFTP
  while true; do
    echo -en "  ${BOLD}Квота хранилища XFTP${NC} ${DIM}(для файлов)${NC} [10gb]: "
    read -r XFTP_QUOTA < "$input_source"
    XFTP_QUOTA="${XFTP_QUOTA:-10gb}"

    # Удобный ввод: "3" -> "3gb"
    if [[ "$XFTP_QUOTA" =~ ^[0-9]+$ ]]; then
      XFTP_QUOTA="${XFTP_QUOTA}gb"
    fi

    # Требуем формат вида Ngb
    if [[ "$XFTP_QUOTA" =~ ^[1-9][0-9]*gb$ ]]; then
      break
    fi

    print_warn "Неверный формат квоты. Используйте: 1gb, 10gb, 100gb"
  done

  # Генерация пароля TURN
  TURN_PASS=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)

  echo ""
  echo -e "  ${DIM}┌─────────────────────────────────────────┐${NC}"
  echo -e "  ${DIM}│${NC}  Итоговая конфигурация:                  ${DIM}│${NC}"
  echo -e "  ${DIM}│${NC}  Адрес:      ${BOLD}${SERVER_ADDR}${NC}"
  echo -e "  ${DIM}│${NC}  SMP порт:   ${BOLD}${SMP_PORT}${NC}"
  echo -e "  ${DIM}│${NC}  XFTP порт:  ${BOLD}${XFTP_PORT}${NC}"
  echo -e "  ${DIM}│${NC}  TURN порт:  ${BOLD}${TURN_PORT}${NC}"
  echo -e "  ${DIM}│${NC}  XFTP квота: ${BOLD}${XFTP_QUOTA}${NC}"
  echo -e "  ${DIM}└─────────────────────────────────────────┘${NC}"
  echo ""
  echo -n "  Продолжить? [Y/n]: "
  read -r confirm < "$input_source"
  if [[ "$confirm" =~ ^[Nn] ]]; then
    echo "Отменено."
    exit 0
  fi
}

# ── Создание файлов ────────────────────────────────────────

create_files() {
  print_step "3/5" "Создание конфигурации"

  mkdir -p "$INSTALL_DIR"
  cd "$INSTALL_DIR"

  mkdir -p smp/config smp/logs
  mkdir -p xftp/config xftp/logs xftp/files

  # docker-compose.yml
  cat > docker-compose.yml << EOF
services:
  smp-server:
    image: simplexchat/smp-server:latest
    container_name: simplex-smp
    restart: unless-stopped
    environment:
      - ADDR=${SERVER_ADDR}
      - WEB_MANUAL=1
    ports:
      - "${SMP_PORT}:5223"
    volumes:
      - ./smp/config:/etc/opt/simplex:z
      - ./smp/logs:/var/opt/simplex:z

  xftp-server:
    image: simplexchat/xftp-server:latest
    container_name: simplex-xftp
    restart: unless-stopped
    environment:
      - ADDR=${SERVER_ADDR}
      - QUOTA=${XFTP_QUOTA}
    ports:
      - "${XFTP_PORT}:443"
    volumes:
      - ./xftp/config:/etc/opt/simplex-xftp:z
      - ./xftp/logs:/var/opt/simplex-xftp:z
      - ./xftp/files:/srv/xftp:z

  coturn:
    image: coturn/coturn:latest
    container_name: simplex-turn
    restart: unless-stopped
    network_mode: host
    command: >
      -n
      --lt-cred-mech
      --fingerprint
      --no-tls
      --no-dtls
      --realm=${SERVER_ADDR}
      --user=simplex:${TURN_PASS}
      --listening-port=${TURN_PORT}
      --min-port=49152
      --max-port=65535
      --log-file=stdout
EOF

  # Сохраняем credentials
  cat > credentials.txt << EOF
# SimpleX Server Credentials
# Сгенерировано: $(date)

SERVER_ADDR=${SERVER_ADDR}
SMP_PORT=${SMP_PORT}
XFTP_PORT=${XFTP_PORT}
TURN_PORT=${TURN_PORT}
TURN_USER=simplex
TURN_PASS=${TURN_PASS}
EOF
  chmod 600 credentials.txt

  print_ok "docker-compose.yml создан"
  print_ok "credentials.txt создан (chmod 600)"
}

# ── Запуск ────────────────────────────────────────────────

start_services() {
  print_step "4/5" "Запуск сервисов"

  cd "$INSTALL_DIR"

  # Удаляем старый контейнер если был
  "${DOCKER_CMD[@]}" rm -f simplex-server 2>/dev/null || true

  print_info "Скачивание образов..."
  "${COMPOSE_CMD[@]}" pull

  print_info "Запуск контейнеров..."
  "${COMPOSE_CMD[@]}" up -d

  # Ждём инициализации
  print_info "Ожидание инициализации (10 сек)..."
  sleep 10
}

# ── Итог ─────────────────────────────────────────────────

print_summary() {
  print_step "5/5" "Готово!"

  cd "$INSTALL_DIR"

  # Нормализуем адрес сервера под внешний HOST:PORT.
  normalize_server_addr() {
    local raw_addr="$1"
    local external_host="$2"
    local external_port="$3"
    echo "$raw_addr" | sed -E "s#@[^:/?]+(:[0-9]+)?#@${external_host}:${external_port}#"
  }

  # Получаем адреса SMP/XFTP из логов
  SMP_ADDR_RAW=$("${DOCKER_CMD[@]}" logs simplex-smp 2>&1 | grep -i "server address" | tail -1 | awk '{print $NF}' || true)
  XFTP_ADDR_RAW=$("${DOCKER_CMD[@]}" logs simplex-xftp 2>&1 | grep -i "server address" | tail -1 | awk '{print $NF}' || true)

  SMP_ADDR=""
  XFTP_ADDR=""
  [ -n "$SMP_ADDR_RAW" ] && SMP_ADDR="$(normalize_server_addr "$SMP_ADDR_RAW" "$SERVER_ADDR" "$SMP_PORT")"
  [ -n "$XFTP_ADDR_RAW" ] && XFTP_ADDR="$(normalize_server_addr "$XFTP_ADDR_RAW" "$SERVER_ADDR" "$XFTP_PORT")"

  echo ""
  echo -e "${GREEN}${BOLD}  ✓ SimpleX серверы запущены!${NC}"
  echo ""
  echo -e "  ${BOLD}Статус контейнеров:${NC}"
  "${COMPOSE_CMD[@]}" ps
  echo ""

  echo -e "  ${BOLD}┌─────────────────────────────────────────────────────────────────┐${NC}"
  echo -e "  ${BOLD}│  Добавьте в приложение SimpleX Chat:                            │${NC}"
  echo -e "  ${BOLD}│                                                                 │${NC}"
  echo -e "  ${BOLD}│  SMP сервер:${NC}                                                    "

  if [ -n "$SMP_ADDR" ]; then
    echo -e "  ${CYAN}  $SMP_ADDR${NC}"
  else
    echo -e "  ${CYAN}  smp://<fingerprint>@${SERVER_ADDR}:${SMP_PORT}${NC}"
    print_info "Точный адрес: ${DOCKER_CMD[*]} logs simplex-smp | grep 'Server address'"
  fi

  echo ""
  echo -e "  ${BOLD}│  XFTP сервер:${NC}"
  if [ -n "$XFTP_ADDR" ]; then
    echo -e "  ${CYAN}  $XFTP_ADDR${NC}"
  else
    echo -e "  ${CYAN}  xftp://<fingerprint>@${SERVER_ADDR}:${XFTP_PORT}${NC}"
    print_info "Точный адрес: ${DOCKER_CMD[*]} logs simplex-xftp | grep 'Server address'"
  fi

  echo ""
  echo -e "  ${BOLD}│  TURN серверы (WebRTC → голос):${NC}"
  echo -e "  ${CYAN}  turn:simplex:${TURN_PASS}@${SERVER_ADDR}:${TURN_PORT}?transport=udp${NC}"
  echo -e "  ${CYAN}  turn:simplex:${TURN_PASS}@${SERVER_ADDR}:${TURN_PORT}?transport=tcp${NC}"
  echo -e "  ${CYAN}  stun:${SERVER_ADDR}:${TURN_PORT}${NC}"
  echo -e "  ${BOLD}└─────────────────────────────────────────────────────────────────┘${NC}"

  echo ""
  echo -e "  ${BOLD}Управление:${NC}"
  echo -e "  ${DIM}cd ${INSTALL_DIR}${NC}"
  echo -e "  ${DIM}${COMPOSE_CMD[*]} logs -f        # логи${NC}"
  echo -e "  ${DIM}${COMPOSE_CMD[*]} down            # остановить${NC}"
  echo -e "  ${DIM}${COMPOSE_CMD[*]} pull && ${COMPOSE_CMD[*]} up -d  # обновить${NC}"
  echo ""
  echo -e "  ${DIM}Все credentials сохранены в: ${INSTALL_DIR}/credentials.txt${NC}"
  echo ""

  # Напоминание про файрвол
  echo -e "  ${YELLOW}${BOLD}⚠  Не забудьте открыть порты в файрволе:${NC}"
  echo -e "  ${DIM}ufw allow ${SMP_PORT}/tcp${NC}"
  echo -e "  ${DIM}ufw allow ${XFTP_PORT}/tcp${NC}"
  echo -e "  ${DIM}ufw allow ${TURN_PORT}/tcp${NC}"
  echo -e "  ${DIM}ufw allow ${TURN_PORT}/udp${NC}"
  echo -e "  ${DIM}ufw allow 49152:65535/udp${NC}"
  echo ""
}

# ── Точка входа ───────────────────────────────────────────

main() {
  clear
  print_banner
  check_deps
  collect_params
  create_files
  start_services
  print_summary
}

main "$@"