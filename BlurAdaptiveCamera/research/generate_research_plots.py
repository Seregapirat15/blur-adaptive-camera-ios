# -*- coding: utf-8 -*-
"""
Демонстрационные графики для исследовательской части отчёта (вариант 14).
Запуск: python generate_research_plots.py
Требуется: pip install matplotlib numpy
"""
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

OUT = Path(__file__).resolve().parent / "figures"
OUT.mkdir(parents=True, exist_ok=True)

# Настройка для отчёта (можно вставить в Word)
plt.rcParams.update({
    "font.size": 11,
    "figure.dpi": 150,
    "axes.grid": True,
    "grid.alpha": 0.3,
})

rng = np.random.default_rng(42)


def figure12_blur_by_scene():
    """M1: Blur / успешность анализа при разных условиях сцены."""
    scenes = [
        "Текст /\nрезкий объект",
        "Слабое\nосвещение",
        "Смаз\nкамеры",
        "Дефокус\n(дальний план)",
    ]
  # Условная доля «успешного» стабильного анализа (1 - normalized blur proxy)
    success_rate = np.array([0.94, 0.81, 0.72, 0.68])
    spread = np.array([0.04, 0.08, 0.10, 0.09])

    fig, ax = plt.subplots(figsize=(8, 4.5))
    x = np.arange(len(scenes))
    bars = ax.bar(x, success_rate, yerr=spread, capsize=5, color="#4C78A8", edgecolor="black", linewidth=0.6)
    ax.axhline(success_rate.mean(), color="#E45756", linestyle="--", linewidth=1.2, label=f"Среднее ≈ {success_rate.mean():.2f}")
    ax.set_xticks(x)
    ax.set_xticklabels(scenes)
    ax.set_ylim(0, 1.05)
    ax.set_ylabel("Доля кадров со стабильной оценкой (усл.)")
    ax.set_title("Рисунок 12 – Оценка размытости при разных условиях сцены")
    ax.legend(loc="lower right")
    fig.tight_layout()
    fig.savefig(OUT / "risunok12_blur_scenes.png")
    plt.close(fig)
    print("Saved", OUT / "risunok12_blur_scenes.png")


def exp_smooth(series: np.ndarray, alpha: float) -> np.ndarray:
    out = np.empty_like(series)
    out[0] = series[0]
    for i in range(1, len(series)):
        out[i] = alpha * series[i] + (1 - alpha) * out[i - 1]
    return out


def figure13_smoothing():
    """M2: Blur до/после сглаживания (alpha как в CameraViewModel ~0.22)."""
    n = 120
    t = np.linspace(0, 4 * np.pi, n)
    raw = 0.45 + 0.25 * np.sin(t) + 0.12 * rng.standard_normal(n)
    raw = np.clip(raw, 0.05, 0.95)
    smooth = exp_smooth(raw, alpha=0.22)

    std_raw = np.std(raw)
    std_smooth = np.std(smooth)

    fig, axes = plt.subplots(1, 2, figsize=(10, 4))
    axes[0].plot(t, raw, label="Blur (сырой)", color="#9ecae1", linewidth=1)
    axes[0].plot(t, smooth, label="Blur (сглаж., α=0,22)", color="#08519c", linewidth=1.5)
    axes[0].set_xlabel("Условное время, с")
    axes[0].set_ylabel("Нормированный Blur")
    axes[0].set_title("Траектория Blur")
    axes[0].legend()
    axes[0].set_ylim(0, 1)

    axes[1].bar(["До сглаживания", "После сглаживания"], [std_raw, std_smooth], color=["#9ecae1", "#08519c"], edgecolor="black")
    axes[1].set_ylabel("Стандартное отклонение")
    axes[1].set_title("Сравнение σ (демонстрационная модель)")

    fig.suptitle("Рисунок 13 – Сглаживание метрики Blur (как в приложении)", y=1.02, fontsize=12)
    fig.tight_layout()
    fig.savefig(OUT / "risunok13_smoothing.png", bbox_inches="tight")
    plt.close(fig)
    print("Saved", OUT / "risunok13_smoothing.png")


def figure14_latency():
    """M3: Гистограмма задержки обработки кадра (мс)."""
    # Смесь: основная масса 25-55 мс, хвост до 90 мс
    core = rng.normal(42, 8, 800)
    tail = rng.uniform(60, 95, 80)
    latency_ms = np.clip(np.concatenate([core, tail]), 15, 100)

    fig, ax = plt.subplots(figsize=(8, 4.5))
    ax.hist(latency_ms, bins=25, color="#59A14F", edgecolor="white", alpha=0.9)
    med = np.median(latency_ms)
    mean = np.mean(latency_ms)
    ax.axvline(med, color="#E45756", linestyle="--", linewidth=1.5, label=f"Медиана ≈ {med:.0f} мс")
    ax.axvline(mean, color="#4C78A8", linestyle=":", linewidth=1.5, label=f"Среднее ≈ {mean:.0f} мс")
    ax.set_xlabel("Задержка обработки кадра, мс")
    ax.set_ylabel("Число кадров (демо. выборка)")
    ax.set_title("Рисунок 14 – Распределение времени конвейера анализа + шарпен")
    ax.legend()
    fig.tight_layout()
    fig.savefig(OUT / "risunok14_latency.png")
    plt.close(fig)
    print("Saved", OUT / "risunok14_latency.png")


if __name__ == "__main__":
    figure12_blur_by_scene()
    figure13_smoothing()
    figure14_latency()
    print("\nГотово. Вставьте PNG из папки research/figures в Word.")
