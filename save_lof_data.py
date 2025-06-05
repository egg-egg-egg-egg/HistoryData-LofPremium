import os
import time
from lof import lof_premium,logger
import datetime
import chinese_calendar

def is_a_share_trading_day(date=None):
    """判断是否为A股交易日"""
    if date is None:
        date = time.localtime()
    y, m, d = date.tm_year, date.tm_mon, date.tm_mday
    return chinese_calendar.is_workday(datetime.date(y, m, d))

def save_lof_data():
    # 在开始时设置默认文件不存在
    if os.getenv('GITHUB_ACTIONS') == 'true':
        with open(os.environ['GITHUB_ENV'], 'a') as f:
            f.write('HAS_FILE=false\n')
    
    if not is_a_share_trading_day():
        print("今日非交易日，跳过数据保存")
        return

    df = lof_premium()
    logger.info(df)
    df.to_csv(f"./data/{datetime.datetime.now().strftime('%Y%m%d')}.csv", encoding='utf-8-sig')
    # 设置文件存在标志（仅GitHub Actions环境）
    if os.getenv('GITHUB_ACTIONS') == 'true':
        with open(os.environ['GITHUB_ENV'], 'a') as f:
            f.write('HAS_FILE=true\n')
if __name__ == "__main__":
    save_lof_data()
