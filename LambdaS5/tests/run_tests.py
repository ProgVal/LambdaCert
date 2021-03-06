#!/usr/bin/env python3

import os
import sys
import glob
import tempfile
import threading
import itertools
import subprocess
from io import BytesIO
import multiprocessing.dummy

TIMEOUT = 240
NB_THREADS = 5

if sys.version_info < (3, 3, 0):
    print('Python >= 3.3 is needed (subprocess timeout support).')
    exit(3)

LJS_BIN = None
if len(sys.argv) == 4:
    (prog, ES5_ENV, LJS_BIN, ljs_tests_dir) = sys.argv
    ljs_tests = glob.glob(os.path.join(ljs_tests_dir, '*.js'))
elif len(sys.argv) == 2:
    ES5_ENV = sys.argv[1]
elif len(sys.argv) == 1:
    ES5_ENV = None
else:
    prog = sys.argv[0]
    print('Syntax: (any of the following)')
    print('\t%s' % prog)
    print('\t%s <env dump>' % prog)
    print('\t%s <env dump> <lambdajs bin> <lambdajs tests dir>' % sys.argv[0])
    exit(2)

TEST_DIR = os.path.dirname(__file__)
EXE = os.path.join(TEST_DIR, '..', 'build', 'eval.native')

def strip_extension(filename):
    return filename[0:-len('.in.ljs')]
def list_ljs(dirname):
    return glob.glob(os.path.join(TEST_DIR, dirname, '*.in.ljs'))
def list_tests(dirname):
    return map(strip_extension, list_ljs(dirname))

tests = map(lambda x:(None, None, x), list_tests('no-env'))

if ES5_ENV:
    tests = itertools.chain(tests,
        map(lambda x:(ES5_ENV, None, x), list_tests('with-env')))
if LJS_BIN:
    tests = itertools.chain(tests,
        map(lambda x:(ES5_ENV, LJS_BIN, x), ljs_tests ))

output_lock = threading.Lock()

successes = []
fails = []
skipped = []
timeout = []
def run_test(env, ljs_bin, test):
    global successes, fails, skipped
    in_ = test + '.in.ljs'
    out = test + '.out.ljs'
    skip = test + '.skip'
    if os.path.isfile(skip):
        with open(skip) as fd:
            skipped.append((test, fd.read()))
        print('%s: skipped.' % test)
        return
    if env:
        command = [EXE, '-load', env]
    else:
        command = [EXE]
    if ljs_bin:
        if 'eval' in test.rsplit('/', 1)[-1].split('.', 1)[0].split('-'):
            skipped.append((test, 'Requires eval'))
            with output_lock:
                print('%s: skipped.' % test)
            return
        with tempfile.TemporaryFile() as desugared:
            subprocess.call([ljs_bin, '-desugar', test, '-print-src'],
                    stdout=desugared)
            desugared.seek(0)
            output = subprocess.check_output(command + ['stdin'],
                    stdin=desugared, stderr=subprocess.DEVNULL, timeout=TIMEOUT)
        output = output.decode()
        if 'passed' in output or 'Passed' in output:
            successes.append(test)
            with output_lock:
                print('%s: ok.' % test)
        else:
            with output_lock:
                sys.stdout.write('%s: %s' % (test, output))
                sys.stdout.flush()
            fails.append(test)
        del desugared
    else:
        with open(in_) as in_fd:
            try:
                output = subprocess.check_output(command + ['stdin'],
                    stdin=in_fd, stderr=subprocess.DEVNULL, timeout=TIMEOUT)
            except subprocess.CalledProcessError:
                fails.append(test)
                return
        with tempfile.TemporaryFile() as out_fd:
            out_fd.write(output)
            out_fd.seek(0)
            with output_lock:
                sys.stdout.write('%s: ' % test)
                sys.stdout.flush()
                if subprocess.call(['diff', '-', out], stdin=out_fd):
                    fails.append(test)
                else:
                    successes.append(test)
                    print('ok.')


stop = False
def test_wrapper(args):
    (env, ljs_bin, test) = args
    global stop
    try:
        if stop:
            return
        run_test(*args)
    except subprocess.TimeoutExpired:
        with output_lock:
            print('%s: timeout' % test)
        timeout.append(test)
    except Exception as e:
        stop = True
        raise

try:
    pool = multiprocessing.dummy.Pool(NB_THREADS)
    pool.map(test_wrapper, tests)
    for (env, ljs_bin, test) in tests:
        threading.Thread(target=test_wrapper, args=(env, ljs_bin, test)).start()
finally:
    with output_lock:
        print('')
        print('Result:')
        print('\t%d successed' % len(successes))
        print('\t%d skipped:' % len(skipped))
        for (test, msg) in skipped:
            print('\t\t%s: %s' % (test, msg))
        print('\t%d timed out:' % len(timeout))
        for test in timeout:
            print('\t\t%s' % test)
        print('\t%d failed:' % len(fails))
        for fail in fails:
            print('\t\t%s' % fail)
if fails:
   exit(1)
else:
    exit(0)
