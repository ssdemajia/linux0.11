#include <linux/kernel.h>
#include <linux/sched.h>
#include <linux/fs.h>
#include <asm/segment.h>

#include <stdarg.h>
#define BUFF_SIZE 4096

extern int sprintf(const char *fmt, ...);

static char proc_buf[BUFF_SIZE] = {'\0'};

int psinfo()
{
    int has_read = 0;
    struct task_struct *p;

    has_read = sprintf(proc_buf, "pid\tstate\tfather\tcounter\tstart_time\n");
    for (int i = 0; i <= NR_TASKS; i++)
    {
        p = task[i];
        if (!p)
            continue;
        has_read += sprintf(proc_buf + has_read, "%d\t", p->pid);
        has_read += sprintf(proc_buf + has_read, "%d\t", p->state);
        has_read += sprintf(proc_buf + has_read, "%d\t", p->father);
        has_read += sprintf(proc_buf + has_read, "%d\t", p->counter);
        has_read += sprintf(proc_buf + has_read, "%d\n", p->start_time);
    }
    return has_read;
}

int hdinfo()
{
    int has_read = 0;
    struct super_block *sb;

    sb = get_super(0x301);
    has_read = sprintf(proc_buf, "Total blocks:%d\n", sb->s_nzones);
    return has_read;
}

int proc_read(int dev, off_t *pos, char *buf, int count)
{
    if (*pos == 0)
    {
        if (dev == 1)
        {
            psinfo();
        }
        else if (dev == 2)
        {
            hdinfo();
        }
    }
    int i = 0;
    for (; i < count; i++) {
        if ((i + *pos) > BUFF_SIZE || proc_buf[*pos] == '\0')
            break; 
        put_fs_byte(proc_buf[i + *pos], buf + i + *pos);
    }
    *pos += i;
    return i; // 要返回读了多少字节
}