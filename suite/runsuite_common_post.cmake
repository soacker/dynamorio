# **********************************************************
# Copyright (c) 2011 Google, Inc.    All rights reserved.
# Copyright (c) 2009-2010 VMware, Inc.    All rights reserved.
# **********************************************************

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# * Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
# 
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# 
# * Neither the name of VMware, Inc. nor the names of its contributors may be
#   used to endorse or promote products derived from this software without
#   specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL VMWARE, INC. OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
# DAMAGE.

# Test suite post-processing
# See instructions in runsuite_common_pre.cmake

cmake_minimum_required (VERSION 2.2)
if (COMMAND cmake_policy)
  # avoid warnings on include()
  cmake_policy(VERSION 2.8)
endif()

# Caller should set build_package boolean and should
# have included runsuite_common_pre.cmake which sets
# last_package_build_dir
if (build_package)
  # PR 534018: pre-commit test suite should test building the full package
  # Plus, we use this for package.cmake now.
  # now package up all the builds
  message("building package in ${last_package_build_dir}")
  file(APPEND "${last_package_build_dir}/CPackConfig.cmake"
    "set(CPACK_INSTALL_CMAKE_PROJECTS\n  ${cpack_projects})")
  set(CTEST_BUILD_COMMAND "${MAKE_COMMAND} package")
  set(CTEST_BUILD_NAME "final package")
  set(CTEST_BINARY_DIRECTORY "${last_package_build_dir}")

  # Remove results from prior build (else ctest_submit() will copy as
  # though results from package build)
  file(GLOB pre_package_res "${last_package_build_dir}/Testing/2*")
  if (EXISTS "${pre_package_res}")
    file(REMOVE_RECURSE "${pre_package_res}")
  endif (EXISTS "${pre_package_res}")

  ctest_start(${SUITE_TYPE})
  ctest_build(BUILD "${CTEST_BINARY_DIRECTORY}")
  ctest_submit() # copy into xml dir
else (build_package)
  # workaround for http://www.cmake.org/Bug/view.php?id=9647
  # it complains and returns error if CTEST_BINARY_DIRECTORY not set at
  # global scope (we do all our real runs inside a function).
  set(CTEST_BUILD_NAME "bug9647workaround")
  set(CTEST_BINARY_DIRECTORY "${last_build_dir}")
  set(CTEST_SOURCE_DIRECTORY "${CTEST_SCRIPT_DIRECTORY}/..")
  set(CTEST_COMMAND "${CTEST_EXECUTABLE_NAME}")
  # it tries to configure+build, but with a start command it does nothing,
  # which is what we want:
  ctest_start(${SUITE_TYPE})
  # actually it still complains so I'm not sure what version I was using where
  # just the start was enough: so we do a test w/ no tests that would match,
  # which does work for cmake 2.6, but not for 2.8: grrr
  # I tried doing a build w/ "make help" and doing a submit,
  # but still says "Error in read script".
  ctest_test(BUILD "${CTEST_BINARY_DIRECTORY}" INCLUDE notestwouldmatchthis)
endif (build_package)

set(outf "${BINARY_BASE}/results.txt")
file(WRITE ${outf} "==================================================\nRESULTS\n\n")
if (arg_already_built)
  file(GLOB all_xml ${RESULTS_DIR}/*Test.xml ${RESULTS_DIR}/*final*Build.xml)
else (arg_already_built)
  file(GLOB all_xml ${RESULTS_DIR}/*Configure.xml ${RESULTS_DIR}/*final*Build.xml)
endif (arg_already_built)
list(SORT all_xml)
foreach (xml ${all_xml})
  get_filename_component(fname "${xml}" NAME_WE)
  string(REGEX REPLACE "^___([^_]+)___.*$" "\\1" build "${fname}")
  file(READ ${xml} string)
  if ("${string}" MATCHES "Configuring incomplete")
    file(APPEND ${outf} "${build}: **** pre-build configure errors ****\n")
  else ("${string}" MATCHES "Configuring incomplete")
    string(REGEX REPLACE "Configure.xml$" "Build.xml" xml "${xml}")
    file(READ ${xml} string)
    string(REGEX MATCHALL "<Error>" build_errors "${string}")
    if (build_errors)
      list(LENGTH build_errors num_errors)
      file(APPEND ${outf} "${build}: **** ${num_errors} build errors ****\n")
      # avoid ; messing up interp as list
      string(REGEX REPLACE ";" ":" string "${string}")
      string(REGEX MATCHALL
        "<Error>[^<]*<BuildLogLine>[^<]*</BuildLogLine>[^<]*<Text>[^<]+<"
        failures "${string}")
      foreach (failure ${failures})
        string(REGEX REPLACE "^.*<Text>([^<]+)<" "\\1" text "${failure}")
        # replace escaped chars for weird quote with simple quote
        string(REGEX REPLACE "&lt:-30&gt:&lt:-128&gt:&lt:-10[34]&gt:" "'" text "${text}")
        string(STRIP "${text}" text)
        file(APPEND ${outf} "\t${text}\n")
      endforeach (failure)
    else (build_errors)
      string(REGEX REPLACE "Build.xml$" "Test.xml" xml "${xml}")
      if (EXISTS ${xml})
        file(READ ${xml} string)
        string(REGEX MATCHALL "Status=\"passed\"" passed "${string}")
        list(LENGTH passed num_passed)
        string(REGEX MATCHALL "Status=\"failed\"" test_errors "${string}")
      else (EXISTS ${xml})
        set(passed OFF)
        set(test_errors OFF)
      endif (EXISTS ${xml})
      if (test_errors)
        list(LENGTH test_errors num_errors)

        # sanity check
        file(GLOB lastfailed build_${build}/Testing/Temporary/LastTestsFailed*.log)
        if (EXISTS "${lastfailed}") # won't exist for package build
          file(READ "${lastfailed}" faillist)
          string(REGEX MATCHALL "\n" faillines "${faillist}")
          list(LENGTH faillines failcount)
          if (NOT failcount EQUAL num_errors)
            message("WARNING: ${num_errors} errors != ${lastfailed} => ${failcount}")
          endif (NOT failcount EQUAL num_errors)
        endif (EXISTS "${lastfailed}")

        file(APPEND ${outf}
          "${build}: ${num_passed} tests passed, **** ${num_errors} tests failed: ****\n")
        # avoid ; messing up interp as list
        string(REGEX REPLACE "&[^;]+;" "" string "${string}")
        string(REGEX REPLACE ";" ":" string "${string}")
        # work around cmake regexps doing maximal matching: we want minimal
        # so we pick a char unlikely to be present to avoid using ".*"
        string(REGEX REPLACE "</Measurement>" "%</Measurement>" string "${string}")
        string(REGEX MATCHALL "Status=\"failed\">[^%]*%</Measurement>"
          failures "${string}")
        # FIXME: have a list of known failures and label w/ " (known: i#XX)"
        foreach (failure ${failures})
          # show key failures like crashes and asserts
          string(REGEX REPLACE "^.*<Name>([^<]+)<.*$" "\\1" name "${failure}")
          error_string("${failure}" reason)
          file(APPEND ${outf} "\t${name} ${reason}\n")
        endforeach (failure)
      else (test_errors)
        if (passed)
          file(APPEND ${outf} "${build}: all ${num_passed} tests passed\n")
        else (passed)
          file(APPEND ${outf} "${build}: build successful; no tests for this build\n")
        endif (passed)
      endif (test_errors)
    endif (build_errors)
  endif ("${string}" MATCHES "Configuring incomplete")
endforeach (xml)

file(READ ${outf} string)
message("${string}")
