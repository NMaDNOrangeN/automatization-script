import sys
import os
import csv
import subprocess
import time
import random
import datetime
import threading
import shutil
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext

# ---------- Базовый путь приложения ----------
if getattr(sys, 'frozen', False):
    BASE_DIR = os.path.dirname(sys.executable)
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

CONFIG_FILE = os.path.join(BASE_DIR, "tools.cfg")
ROOT_FILE = os.path.join(BASE_DIR, "root.cfg")
REPORT_DIR = os.path.join(BASE_DIR, "reports")
LOG_DIR = os.path.join(REPORT_DIR, "logs")
LOG_FILE = os.path.join(REPORT_DIR, "launch_log.csv")
REPORT_FILE = os.path.join(REPORT_DIR, "report.txt")
LOCK_DIR = os.path.join(REPORT_DIR, "log.lock")

# ---------- Функции работы с конфигурацией ----------
def load_root():
    if os.path.exists(ROOT_FILE):
        with open(ROOT_FILE, 'r', encoding='utf-8') as f:
            line = f.readline().strip()
            if line:
                return line.rstrip('\\')
    return None

def save_root(path):
    with open(ROOT_FILE, 'w', encoding='utf-8') as f:
        if path:
            f.write(path.rstrip('\\'))

def load_tools():
    """Возвращает список словарей {name, type, path}"""
    tools = []
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and '=' in line and not line.startswith(';'):
                    name, rest = line.split('=', 1)
                    if '|' in rest:
                        ttype, path = rest.split('|', 1)
                        ttype = ttype.strip()
                        path = path.strip().strip('"')
                    else:
                        ttype, path = 'gui', rest  # совместимость со старыми записями
                    tools.append({'name': name.strip(), 'type': ttype.strip(), 'path': path.strip()})
    return tools

def save_tools(tools):
    with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
        for t in tools:
            f.write(f"{t['name']}={t['type']}|{t['path']}\n")

def resolve_path(relative_path, root):
    if not relative_path:
        return ""
    if os.path.isabs(relative_path) or relative_path.startswith('\\\\'):
        return relative_path
    if root:
        return os.path.join(root, relative_path)
    return relative_path

# ---------- Блокировка для лога (аналог mkdir lock) ----------
def acquire_log_lock():
    """Пытается создать директорию-замок. Возвращает True, если удалось."""
    for _ in range(50):
        try:
            os.mkdir(LOCK_DIR)
            return True
        except OSError:
            time.sleep(1)
    return False

def release_log_lock():
    try:
        os.rmdir(LOCK_DIR)
    except OSError:
        pass

def write_log(date_str, time_str, tool, exit_code, log_path):
    """Потокобезопасная запись в CSV."""
    if not acquire_log_lock():
        print("[Ошибка] Не удалось захватить блокировку лога.")
        return
    try:
        file_exists = os.path.isfile(LOG_FILE)
        with open(LOG_FILE, 'a', newline='', encoding='utf-8') as f:
            writer = csv.writer(f, delimiter=';')
            if not file_exists:
                writer.writerow(['Date', 'Time', 'Tool', 'ExitCode', 'OutputLog'])
            writer.writerow([date_str, time_str, tool, exit_code, log_path])
    finally:
        release_log_lock()

# ---------- Запуск инструментов ----------
def worker_process(tool_name):
    """Точка входа для скрытого воркера (параллельный запуск)."""
    tools = load_tools()
    root = load_root()
    tool = next((t for t in tools if t['name'] == tool_name), None)
    if not tool:
        write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                  tool_name, 'NOT_FOUND', '')
        return
    exe_path = resolve_path(tool['path'], root).strip('"')
    if not os.path.exists(exe_path):
        write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                  tool_name, 'FILE_NOT_FOUND', '')
        return

    if tool['type'] == 'console':
        subprocess.Popen(
            f'start "Tool_{tool["name"]}" cmd /k "cd /d ""{os.path.dirname(exe_path)}"" && ""{exe_path}""',
            shell=True,
            creationflags=subprocess.CREATE_NEW_CONSOLE
        )
        write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                  tool_name, '0', 'Started (interactive)')
    else:
        # GUI – запускаем с перенаправлением вывода в лог
        stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + f'_{random.randint(1000,9999)}'
        log_path = os.path.join(LOG_DIR, f"{tool_name}_{stamp}.log")
        os.makedirs(LOG_DIR, exist_ok=True)
        try:
            with open(log_path, 'w', encoding='utf-8') as log_f:
                proc = subprocess.Popen([exe_path], stdout=log_f, stderr=subprocess.STDOUT,
                                        creationflags=subprocess.CREATE_NO_WINDOW)
                proc.wait()
            exit_code = str(proc.returncode)
        except Exception as e:
            exit_code = 'ERROR'
            with open(log_path, 'w', encoding='utf-8') as log_f:
                log_f.write(str(e))
        # Удаляем пустой лог
        if os.path.exists(log_path) and os.path.getsize(log_path) == 0:
            os.remove(log_path)
            log_path = ''
        write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                  tool_name, exit_code, log_path)

# ---------- GUI приложение ----------
class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Лаунчер сборки")
        self.geometry("900x600")
        self.root_path = load_root()
        self.tools = load_tools()

        # Создаём вкладки
        self.notebook = ttk.Notebook(self)
        self.tab_run = ttk.Frame(self.notebook)
        self.tab_editor = ttk.Frame(self.notebook)
        self.tab_report = ttk.Frame(self.notebook)
        self.notebook.add(self.tab_run, text="Запуск")
        self.notebook.add(self.tab_editor, text="Редактор")
        self.notebook.add(self.tab_report, text="Отчёт")
        self.notebook.pack(expand=True, fill='both')

        self.build_run_tab()
        self.build_editor_tab()
        self.build_report_tab()

        self.refresh_tools_list()

    # ---------- Вкладка "Запуск" ----------
    def build_run_tab(self):
        frame = ttk.Frame(self.tab_run)
        frame.pack(fill='both', expand=True, padx=10, pady=10)

        # Список инструментов с чекбоксами
        ttk.Label(frame, text="Доступные инструменты:").pack(anchor='w')
        self.tools_listbox = tk.Listbox(frame, selectmode='multiple', height=15)
        self.tools_listbox.pack(fill='both', expand=True, pady=5)

        btn_frame = ttk.Frame(frame)
        btn_frame.pack(fill='x', pady=5)
        ttk.Button(btn_frame, text="Запустить выбранное (последовательно)",
                   command=self.run_selected_sequential).pack(side='left', padx=5)
        ttk.Button(btn_frame, text="Запустить выбранное (параллельно)",
                   command=self.run_selected_parallel).pack(side='left', padx=5)
        ttk.Button(btn_frame, text="Обновить список", command=self.refresh_tools_list).pack(side='left', padx=5)

        # Статус
        self.status_var = tk.StringVar()
        ttk.Label(frame, textvariable=self.status_var).pack(anchor='w', pady=5)

    def refresh_tools_list(self):
        self.tools = load_tools()
        self.root_path = load_root()
        self.tools_listbox.delete(0, 'end')
        for i, t in enumerate(self.tools, 1):
            self.tools_listbox.insert('end', f"{i}. {t['name']} [{t['type']}]")
        self.status_var.set(f"Корневой путь: {self.root_path if self.root_path else 'не задан'}")

    def run_selected_sequential(self):
        selected = self.tools_listbox.curselection()
        if not selected:
            messagebox.showwarning("Предупреждение", "Выберите хотя бы один инструмент.")
            return
        for idx in selected:
            tool = self.tools[idx]
            self.status_var.set(f"Запуск: {tool['name']}...")
            self.update()
            if tool['type'] == 'console':
                # Для консольных показываем диалог
                result = self.console_dialog(tool)
                if result is None:  # пользователь закрыл диалог
                    continue
                if result == 'INTERACTIVE':
                    # Интерактивный режим (как в оригинале)
                    exe_path = resolve_path(tool['path'], self.root_path).strip('"')
                    if os.path.exists(exe_path):
                        subprocess.Popen(
                            f'start "Tool_{tool["name"]}" cmd /k "cd /d ""{os.path.dirname(exe_path)}"" && ""{exe_path}""',
                            shell=True,
                            creationflags=subprocess.CREATE_NEW_CONSOLE
                        )
                        write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                                tool['name'], '0', 'Started (interactive)')
                    else:
                        write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                                tool['name'], 'FILE_NOT_FOUND', '')
                        messagebox.showerror("Ошибка", f"Файл не найден: {exe_path}")
                # Режим с параметрами уже выполнен внутри диалога, ничего не делаем
            else:
                # GUI инструмент
                exe_path = resolve_path(tool['path'], self.root_path).strip('"')
                if not os.path.exists(exe_path):
                    write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                            tool['name'], 'FILE_NOT_FOUND', '')
                    messagebox.showerror("Ошибка", f"Файл не найден: {exe_path}")
                    continue
                stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + f'_{random.randint(1000,9999)}'
                log_path = os.path.join(LOG_DIR, f"{tool['name']}_{stamp}.log")
                os.makedirs(LOG_DIR, exist_ok=True)
                try:
                    with open(log_path, 'w', encoding='utf-8') as log_f:
                        proc = subprocess.Popen([exe_path], stdout=log_f, stderr=subprocess.STDOUT,
                                                creationflags=subprocess.CREATE_NO_WINDOW)
                        proc.wait()
                    exit_code = str(proc.returncode)
                except Exception as e:
                    exit_code = 'ERROR'
                    with open(log_path, 'w', encoding='utf-8') as log_f:
                        log_f.write(str(e))
                if os.path.exists(log_path) and os.path.getsize(log_path) == 0:
                    os.remove(log_path)
                    log_path = ''
                write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                        tool['name'], exit_code, log_path)
        self.status_var.set("Готово.")

    def run_selected_parallel(self):
        selected = self.tools_listbox.curselection()
        if not selected:
            messagebox.showwarning("Предупреждение", "Выберите хотя бы один инструмент.")
            return
        for idx in selected:
            tool = self.tools[idx]
            self.status_var.set(f"Запуск в фоне: {tool['name']}...")
            self.update()
            # Запускаем самого себя как воркер
            subprocess.Popen([sys.executable, os.path.abspath(__file__), '__worker__', tool['name']],
                             creationflags=subprocess.CREATE_NO_WINDOW)
        self.status_var.set("Выбранные инструменты запущены параллельно.")

    def run_console_with_args_dialog(self, tool):
        """Диалог для консольного инструмента: выбор режима и, если нужно, параметров.
        Возвращает (exit_code, log_path) или 'INTERACTIVE', если выбран интерактивный режим."""
        dialog = tk.Toplevel(self)
        dialog.title(f"Запуск: {tool['name']}")
        dialog.geometry("400x200")
        dialog.transient(self)
        dialog.grab_set()

        ttk.Label(dialog, text="Режим запуска:").pack(pady=5)
        mode_var = tk.StringVar(value="interactive")
        ttk.Radiobutton(dialog, text="Интерактивный (окно cmd)", variable=mode_var, value="interactive").pack(anchor='w', padx=20)
        ttk.Radiobutton(dialog, text="С параметрами (вывод в лог)", variable=mode_var, value="with_args").pack(anchor='w', padx=20)

        args_var = tk.StringVar()
        args_frame = ttk.Frame(dialog)
        args_frame.pack(pady=5, fill='x', padx=10)
        ttk.Label(args_frame, text="Параметры:").pack(side='left')
        ttk.Entry(args_frame, textvariable=args_var, width=30).pack(side='left', padx=5)

        def on_ok():
            if mode_var.get() == "with_args":
                args = args_var.get().strip()
                # Запуск с параметрами
                exe_path = resolve_path(tool['path'], self.root_path).strip('"')
                if not os.path.exists(exe_path):
                    messagebox.showerror("Ошибка", f"Файл не найден: {exe_path}", parent=dialog)
                    dialog.destroy()
                    return 'FILE_NOT_FOUND', ''
                stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + f'_{random.randint(1000,9999)}'
                log_path = os.path.join(LOG_DIR, f"{tool['name']}_{stamp}.log")
                os.makedirs(LOG_DIR, exist_ok=True)
                try:
                    cmd = [exe_path] + args.split()
                    with open(log_path, 'w', encoding='utf-8') as log_f:
                        proc = subprocess.Popen(cmd, stdout=log_f, stderr=subprocess.STDOUT,
                                                cwd=os.path.dirname(exe_path),
                                                creationflags=subprocess.CREATE_NO_WINDOW)
                        proc.wait()
                    exit_code = str(proc.returncode)
                except Exception as e:
                    exit_code = 'ERROR'
                    with open(log_path, 'w', encoding='utf-8') as log_f:
                        log_f.write(str(e))
                write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                        tool['name'], exit_code, log_path)
                dialog.destroy()
                return exit_code, log_path
            else:
                dialog.destroy()
                return 'INTERACTIVE', ''

        ttk.Button(dialog, text="OK", command=on_ok).pack(pady=10)
        self.wait_window(dialog)
        # После закрытия окна
        return getattr(self, '_console_result', ('INTERACTIVE', ''))
    
    def console_dialog(self, tool):
        dialog = tk.Toplevel(self)
        dialog.title(f"Запуск: {tool['name']}")
        dialog.geometry("400x200")
        dialog.transient(self)
        dialog.grab_set()
        dialog.update_idletasks()  # чтобы размеры окна определились
        width = dialog.winfo_width()
        height = dialog.winfo_height()
        x = (dialog.winfo_screenwidth() // 2) - (width // 2)
        y = (dialog.winfo_screenheight() // 2) - (height // 2)
        dialog.geometry(f'+{x}+{y}')
        result = []

        def on_interactive():
            result.append('INTERACTIVE')
            dialog.destroy()

        def on_args():
            args = args_var.get().strip()
            exe_path = resolve_path(tool['path'], self.root_path).strip('"')
            if not os.path.exists(exe_path):
                messagebox.showerror("Ошибка", f"Файл не найден: {exe_path}", parent=dialog)
                return
            stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S') + f'_{random.randint(1000,9999)}'
            log_path = os.path.join(LOG_DIR, f"{tool['name']}_{stamp}.log")
            os.makedirs(LOG_DIR, exist_ok=True)
            try:
                cmd = [exe_path] + args.split()
                with open(log_path, 'w', encoding='utf-8') as log_f:
                    proc = subprocess.Popen(cmd, stdout=log_f, stderr=subprocess.STDOUT,
                                            cwd=os.path.dirname(exe_path),
                                            creationflags=subprocess.CREATE_NO_WINDOW)
                    proc.wait()
                exit_code = str(proc.returncode)
            except Exception as e:
                exit_code = 'ERROR'
                with open(log_path, 'w', encoding='utf-8') as log_f:
                    log_f.write(str(e))
            write_log(datetime.date.today().isoformat(), datetime.datetime.now().strftime('%H:%M:%S'),
                    tool['name'], exit_code, log_path)
            result.append('ARGS_DONE')
            dialog.destroy()

        ttk.Label(dialog, text="Режим запуска:").pack(pady=5)
        ttk.Button(dialog, text="Интерактивный (окно cmd)", command=on_interactive).pack(pady=2)
        args_frame = ttk.Frame(dialog)
        args_frame.pack(pady=5, fill='x', padx=10)
        ttk.Label(args_frame, text="Параметры:").pack(side='left')
        args_var = tk.StringVar()
        ttk.Entry(args_frame, textvariable=args_var, width=30).pack(side='left', padx=5)
        ttk.Button(dialog, text="Запустить с параметрами", command=on_args).pack(pady=5)

        self.wait_window(dialog)
        return result[0] if result else None

    # ---------- Вкладка "Редактор" ----------
    def build_editor_tab(self):
        frame = ttk.Frame(self.tab_editor)
        frame.pack(fill='both', expand=True, padx=10, pady=10)

        # Кнопки управления корневым путём
        path_frame = ttk.LabelFrame(frame, text="Корневой путь")
        path_frame.pack(fill='x', pady=5)
        self.root_var = tk.StringVar(value=self.root_path or "")
        ttk.Entry(path_frame, textvariable=self.root_var, width=80).pack(side='left', padx=5, expand=True, fill='x')
        ttk.Button(path_frame, text="Сохранить", command=self.save_root_path).pack(side='left', padx=5)

        # Список инструментов в редакторе
        ttk.Label(frame, text="Список инструментов:").pack(anchor='w')
        list_frame = ttk.Frame(frame)
        list_frame.pack(fill='both', expand=True, pady=5)
        self.editor_listbox = tk.Listbox(list_frame, height=10)
        self.editor_listbox.pack(side='left', fill='both', expand=True)
        scrollbar = ttk.Scrollbar(list_frame, orient='vertical', command=self.editor_listbox.yview)
        scrollbar.pack(side='right', fill='y')
        self.editor_listbox.config(yscrollcommand=scrollbar.set)
        self.editor_listbox.bind('<<ListboxSelect>>', self.on_editor_select)

        btn_frame = ttk.Frame(frame)
        btn_frame.pack(fill='x', pady=5)
        ttk.Button(btn_frame, text="Добавить", command=self.add_tool).pack(side='left', padx=5)
        ttk.Button(btn_frame, text="Изменить", command=self.edit_tool).pack(side='left', padx=5)
        ttk.Button(btn_frame, text="Удалить", command=self.delete_tool).pack(side='left', padx=5)
        ttk.Button(btn_frame, text="Обновить", command=self.refresh_editor_list).pack(side='left', padx=5)

        # Форма редактирования
        detail_frame = ttk.LabelFrame(frame, text="Детали инструмента")
        detail_frame.pack(fill='x', pady=5)
        ttk.Label(detail_frame, text="Имя:").grid(row=0, column=0, sticky='w', padx=5, pady=2)
        self.edit_name_var = tk.StringVar()
        ttk.Entry(detail_frame, textvariable=self.edit_name_var, width=40).grid(row=0, column=1, padx=5, pady=2)

        ttk.Label(detail_frame, text="Тип:").grid(row=1, column=0, sticky='w', padx=5, pady=2)
        self.edit_type_var = tk.StringVar(value='gui')
        ttk.Combobox(detail_frame, textvariable=self.edit_type_var, values=['gui', 'console'], state='readonly',
                     width=10).grid(row=1, column=1, sticky='w', padx=5, pady=2)

        ttk.Label(detail_frame, text="Путь:").grid(row=2, column=0, sticky='w', padx=5, pady=2)
        self.edit_path_var = tk.StringVar()
        ttk.Entry(detail_frame, textvariable=self.edit_path_var, width=60).grid(row=2, column=1, padx=5, pady=2)

    def refresh_editor_list(self):
        self.tools = load_tools()
        self.editor_listbox.delete(0, 'end')
        for t in self.tools:
            self.editor_listbox.insert('end', f"{t['name']} [{t['type']}] -> {t['path']}")

    def on_editor_select(self, event):
        selection = self.editor_listbox.curselection()
        if not selection:
            return
        tool = self.tools[selection[0]]
        self.edit_name_var.set(tool['name'])
        self.edit_type_var.set(tool['type'])
        self.edit_path_var.set(tool['path'])

    def save_root_path(self):
        new_root = self.root_var.get().strip()
        save_root(new_root)
        self.root_path = new_root
        self.refresh_tools_list()
        self.refresh_editor_list()
        messagebox.showinfo("Успех", "Корневой путь сохранён.")

    def add_tool(self):
        name = self.edit_name_var.get().strip()
        ttype = self.edit_type_var.get()
        path = self.edit_path_var.get().strip()
        if not name or not path:
            messagebox.showerror("Ошибка", "Имя и путь не могут быть пустыми.")
            return
        if any(t['name'] == name for t in self.tools):
            messagebox.showerror("Ошибка", "Инструмент с таким именем уже существует.")
            return
        self.tools.append({'name': name, 'type': ttype, 'path': path})
        save_tools(self.tools)
        self.refresh_editor_list()
        self.refresh_tools_list()
        messagebox.showinfo("Успех", "Инструмент добавлен.")

    def edit_tool(self):
        selection = self.editor_listbox.curselection()
        if not selection:
            messagebox.showwarning("Предупреждение", "Выберите инструмент для изменения.")
            return
        idx = selection[0]
        new_name = self.edit_name_var.get().strip()
        new_type = self.edit_type_var.get()
        new_path = self.edit_path_var.get().strip()
        if not new_name or not new_path:
            messagebox.showerror("Ошибка", "Имя и путь не могут быть пустыми.")
            return
        # Проверка на дубликат имени (кроме текущего)
        if any(t['name'] == new_name for i, t in enumerate(self.tools) if i != idx):
            messagebox.showerror("Ошибка", "Инструмент с таким именем уже существует.")
            return
        self.tools[idx] = {'name': new_name, 'type': new_type, 'path': new_path}
        save_tools(self.tools)
        self.refresh_editor_list()
        self.refresh_tools_list()
        messagebox.showinfo("Успех", "Инструмент обновлён.")

    def delete_tool(self):
        selection = self.editor_listbox.curselection()
        if not selection:
            messagebox.showwarning("Предупреждение", "Выберите инструмент для удаления.")
            return
        if messagebox.askyesno("Подтверждение", "Удалить выбранный инструмент?"):
            del self.tools[selection[0]]
            save_tools(self.tools)
            self.refresh_editor_list()
            self.refresh_tools_list()

    # ---------- Вкладка "Отчёт" ----------
    def build_report_tab(self):
        frame = ttk.Frame(self.tab_report)
        frame.pack(fill='both', expand=True, padx=10, pady=10)

        ttk.Button(frame, text="Сформировать отчёт", command=self.generate_report).pack(anchor='w', pady=5)
        self.report_text = scrolledtext.ScrolledText(frame, wrap='word', height=25)
        self.report_text.pack(fill='both', expand=True)

    def generate_report(self):
        if not os.path.exists(LOG_FILE):
            self.report_text.delete('1.0', 'end')
            self.report_text.insert('1.0', "Лог-файл отсутствует.")
            return

        total = ok = fail = 0
        rows = []
        with open(LOG_FILE, 'r', encoding='utf-8') as f:
            reader = csv.reader(f, delimiter=';')
            header = next(reader, None)
            for row in reader:
                if len(row) >= 4:
                    total += 1
                    if row[3].strip().upper() == 'FILE_NOT_FOUND':
                        fail += 1
                    else:
                        ok += 1
                    rows.append(row)

        report_lines = []
        report_lines.append("ОТЧЁТ О ЗАПУСКАХ ИНСТРУМЕНТОВ")
        report_lines.append(f"Сформирован: {datetime.datetime.now().strftime('%d.%m.%Y %H:%M:%S')}")
        report_lines.append(f"Всего запусков: {total}")
        report_lines.append(f"Успешных: {ok}")
        report_lines.append(f"Ошибок/не найдено: {fail}")
        report_lines.append("=" * 60)
        report_lines.append(f"{'Дата':<12} | {'Время':<10} | {'Инструмент':<20} | {'Код':<8} | {'Лог'}")
        report_lines.append("-" * 60)
        for r in rows:
            log_name = os.path.basename(r[4]) if r[4] else ""
            report_lines.append(f"{r[0]:<12} | {r[1]:<10} | {r[2]:<20} | {r[3]:<8} | {log_name}")
        report_lines.append("=" * 60)
        report_lines.append("\nЛОГИ ВЫВОДА ИНСТРУМЕНТОВ\n")
        for r in rows:
            if r[4] and os.path.exists(r[4]):
                report_lines.append(f"Инструмент: {r[2]}")
                report_lines.append(f"Код возврата: {r[3]}")
                with open(r[4], 'r', encoding='utf-8', errors='replace') as lf:
                    report_lines.append(lf.read())
                report_lines.append("-" * 40)

        with open(REPORT_FILE, 'w', encoding='utf-8') as rf:
            rf.write('\n'.join(report_lines))

        self.report_text.delete('1.0', 'end')
        self.report_text.insert('1.0', '\n'.join(report_lines))
        messagebox.showinfo("Готово", f"Отчёт сохранён: {REPORT_FILE}")

# ---------- Точка входа ----------
if __name__ == '__main__':
    # Создаём необходимые папки
    os.makedirs(REPORT_DIR, exist_ok=True)
    os.makedirs(LOG_DIR, exist_ok=True)
    if not os.path.exists(CONFIG_FILE):
        open(CONFIG_FILE, 'w').close()
    if not os.path.exists(ROOT_FILE):
        open(ROOT_FILE, 'w').close()

    if len(sys.argv) > 1 and sys.argv[1] == '__worker__':
        # Режим воркера
        tool_name = sys.argv[2] if len(sys.argv) > 2 else None
        if tool_name:
            worker_process(tool_name)
        sys.exit(0)
    else:
        # Запуск GUI
        app = App()
        app.mainloop()